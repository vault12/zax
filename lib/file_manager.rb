# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'base32'

class FileManager
  include Utils
  include Errors
  include Helpers::TransactionHelper

  STATUS_CODES = %i(NOT_FOUND START UPLOADING COMPLETE)

  # Minimum acceptable secret_seed length. A shorter established seed is a fatal misconfiguration (see _check_seed_source).
  MIN_SEED_LEN = 32

  attr_reader :storage_path
  attr_reader :max_chunk_size
  attr_reader :per_chunk_overhead
  attr_reader :prune_grace
  attr_reader :seed

  def self.is_enabled?
    Rails.configuration.x.relay.file_store[:enabled]
  end

  def self.mode?
    Rails.configuration.x.relay.file_store[:mode]
  end

  def self.test_mode?
    self.mode? == :test
  end

  def initialize(ctrl =nil)
    @controller = ctrl # parent controller to report errors

    fsr = Rails.configuration.x.relay.file_store[:root]
    @storage_path = (not fsr.empty?) ? fsr : "#{Rails.root}/shared/uploads/"

    # ensure it always terminated by '/'
    @storage_path+='/' unless @storage_path.last == '/'

    _ensure_storage_dir()
    _ensure_secret_seed()

    @max_chunk_size = Rails.configuration.x.relay.file_store[:max_chunk_size]
    @max_chunk_size = 100*1024 if @max_chunk_size.nil? or @max_chunk_size<1

    @per_chunk_overhead = Rails.configuration.x.relay.file_store[:per_chunk_overhead]
    @per_chunk_overhead = 128 if @per_chunk_overhead.nil? or @per_chunk_overhead<0

    @prune_grace = Rails.configuration.x.relay.file_store[:prune_grace]
    @prune_grace = 3600 if @prune_grace.nil? or @prune_grace<0

    # TODO: new class to trigger severe_error
    # Reserve 1k for command wrappers
    if @max_chunk_size >= MAX_COMMAND_BODY - 1024
      fail ConfigError.new @controller,
        msg: "`max_chunk_size` config param have to be 1kb smaller then MAX_COMMAND_BODY build constant"
    end

    # The sender quota is charged with declared file sizes, so a file larger
    # than the whole quota could never be declared — refuse to boot instead
    # of silently rejecting every big upload at runtime.
    quota    = Rails.configuration.x.relay.file_store[:max_storage_bytes]
    max_file = Rails.configuration.x.relay.file_store[:max_file_size]
    if quota and quota > 0 and max_file and quota < max_file
      fail ConfigError.new @controller,
        msg: "`max_storage_bytes` (#{quota}) is below `max_file_size` (#{max_file}): the largest declarable file would never fit the sender quota"
    end
  end

  def create_storage_token(hpk_from,hpk_to,nonce,msz)
    uID = h2(hpk_from+hpk_to+nonce+@seed)
    storage_id = storage_from_upload(uID)
    { hpk_from: hpk_from,
      hpk_to: hpk_to,
      file_size: msz,
      uploadID: uID,
      storage_id: storage_id,
      storage_name: storage_name_from_id(storage_id),
    }
  end

  def storage_from_upload(uploadID)
    h2(uploadID+@seed)
  end

  # Pure mapping, also needed by Mailbox to reap file indexes without paying for a full FileManager (config/dir/seed) instantiation
  def self.storage_name_from_id(storage_id, part = nil)
    name = Base32.encode(storage_id).gsub('=','').downcase
    part ? "#{name}.#{part}.bin" : name
  end

  def storage_name_from_id(storage_id, part = nil)
    self.class.storage_name_from_id(storage_id, part)
  end

  def save_data(uploadID, data, part)
    file_name = storage_name_from_id storage_from_upload(uploadID), part
    File.open("#{storage_path}#{file_name}", 'wb') do |f|
      f.write data
      f.flush
    end
  end

  def load_data(uploadID, part)
    data = nil
    file_name = storage_name_from_id storage_from_upload(uploadID), part
    File.open("#{storage_path}#{file_name}", 'rb') do |f|
      data = f.read
    end
    return data
  rescue Errno::ENOENT
    # A recorded part whose chunk is missing on disk (crash window, disk loss) — nil lets the caller answer NOT_FOUND 
    nil
  end

  def delete_file(uploadID)
    storage_name = storage_name_from_id(storage_from_upload(uploadID))
    # Drop the tracking key first: if the on-disk delete below fails partway, the
    # file is now untracked and the orphan sweep will finish removing its chunks.
    rds.del "#{STORAGE_PREFIX}#{storage_name}"
    return if self.class.test_mode?
    # Delete every chunk on disk for this upload by its storage name, whatever the
    # part indices were. `parts` is an index-keyed list, so total_chunks
    # is a COUNT decoupled from the indices — a 0...count loop missed sparse/out-of-
    # order chunks and left ciphertext behind. Globbing destroys exactly what exists.
    _delete_chunks storage_name, 'delete'
  end

  # Reap uploads that never completed within stalled_upload_expiration.
  # A live tracking key holds the upload lifecycle in its value: START from
  # startFileUpload, COMPLETE once the last chunk landed (Mailbox#
  # mark_file_complete). Only START entries older than the threshold are
  # deleted — a COMPLETE file awaiting download lives out files_expiration.
  # Age is derived from the tracking key's TTL, so no extra timestamps are
  # stored. Clients restart interrupted uploads with a fresh uploadID, so a
  # stalled upload is garbage that would otherwise hold its declared bytes
  # against the sender's quota (and its chunks on disk) for the full week.
  # Legacy entries written as "1" before this lifecycle existed are skipped
  # and age out via their TTL.
  def delete_stalled_uploads
    threshold = Rails.configuration.x.relay.file_store[:stalled_upload_expiration]
    return unless threshold and threshold > 0
    lifetime = Rails.configuration.x.relay.file_store[:files_expiration]
    return unless lifetime and lifetime > threshold

    tracked = rds.smembers(ZAX_GLOBAL_FILES)
    return if tracked.empty?
    states = rds.pipelined do |pipe|
      tracked.each do |tag|
        pipe.get tag
        pipe.ttl tag
      end
    end
    tracked.each_with_index do |tag, i|
      value, ttl = states[2 * i], states[2 * i + 1].to_i
      next unless value == 'START'
      next unless ttl.positive? && lifetime - ttl > threshold
      # The snapshot above is stale by the time we act on it: the last chunk
      # of this upload may be committing right now (mark_file_complete runs
      # inside the upload's MULTI, and its WATCH is on the file lock, not on
      # this key). Reap under a WATCH on the tag with a guarded re-read: a
      # concurrent write to the tag aborts our EXEC, and the retry stands
      # down once the fresh read is no longer a stalled START.
      reaped = false
      runRedisTransaction(tag, nil, 'reap stalled upload', Proc.new {
        [rds.get(tag), rds.ttl(tag).to_i]
      }) do |(val, tl), rds_transaction|
        reaped = val == 'START' && tl.positive? && lifetime - tl > threshold
        next unless reaped # empty MULTI: fresh state says leave it alone
        rds_transaction.del tag
        rds_transaction.srem(ZAX_GLOBAL_FILES, tag)
      end
      # Disk chunks go only once the key delete has committed; if the reap
      # stood down the file is live and its chunks must stay.
      _delete_chunks tag.sub(STORAGE_PREFIX, ''), 'stalled' if reaped && !self.class.test_mode?
    end
  end

  def delete_expired_all
    # Phase 1: reconcile the tracked set — drop members whose tracking key has
    # expired and delete their on-disk chunks. (A live upload keeps its tracking
    # key, so it is never reached here.) Liveness of the whole set is checked
    # in one pipelined round-trip.
    tracked = rds.smembers(ZAX_GLOBAL_FILES)
    unless tracked.empty?
      present = rds.pipelined { |pipe| tracked.each { |t| pipe.exists t } }
      dead = tracked.each_index.select { |i| present[i].to_i == 0 }.map { |i| tracked[i] }
      unless dead.empty?
        rds.srem(ZAX_GLOBAL_FILES, *dead)
        dead.each { |name| _delete_chunks name.sub(STORAGE_PREFIX, ''), 'expired' }
      end
    end

    # Phase 2: prune truly-orphaned chunk files (on disk with no live tracking
    # key). Chunks are grouped by upload so liveness costs ONE pipelined EXISTS
    # per upload, not per chunk. The batch runs right before the deletes (never
    # a job-start snapshot), and a freshly-written file is spared by the mtime
    # grace — so an upload landing while this job runs, even between the
    # liveness batch and its delete, cannot be pruned.
    by_name = Dir["#{storage_path}*.*.bin"].group_by do |file|
      file.sub(/\.\d*\.bin/, '').match(/\w*$/)[0]
    end
    by_name.delete(nil)
    by_name.delete('')
    return if by_name.empty?

    names = by_name.keys
    present = rds.pipelined { |pipe| names.each { |n| pipe.exists "#{STORAGE_PREFIX}#{n}" } }
    now = Time.now
    names.each_with_index do |name, i|
      next if present[i].to_i > 0 # still tracked => keep
      by_name[name].each do |file|
        next if now - File.mtime(file) < @prune_grace # too fresh => keep
        File.delete file
        logger.info "#{INFO} Prunning orphan #{file}"
      rescue Errno::ENOENT
        next # file vanished between listing and deletion — already gone, fine
      end
    end
  end

  def _delete_chunks(storage_name, reason)
    # Storage names are deterministic (the same sender, recipient and message
    # nonce recreate the same name once the original is deleted or expired),
    # so a re-declared upload can land chunks between the tracking-key delete
    # and this glob. Skip anything written after we started: those chunks
    # belong to the new incarnation. A false skip is merely an orphan for the
    # sweep to collect; a false delete would eat a live upload's data.
    cutoff = Time.now
    Dir["#{storage_path}#{storage_name}.*.bin"].each do |file|
      next if File.mtime(file) > cutoff
      File.delete file
      logger.info "#{INFO} Delete #{reason} #{file}"
    rescue Errno::ENOENT
      next
    end
  end

  private
  def _ensure_storage_dir
    FileUtils.mkdir_p(@storage_path) unless File.directory?(@storage_path)
  end

  def _seed_path
    @storage_path+"secret_seed.txt"
  end

  # Load an already-established seed, in precedence order:
  #   1. config  config.x.relay.file_store[:secret_seed]
  #   2. ENV     ZAX_SECRET_SEED   (deployments that inject secrets via env)
  #   3. file    <storage>/secret_seed.txt   (the usual production location)
  # Sets @seed and returns true if any source yields a >=32-char seed. Never
  # writes anything — establishing a NEW seed is _establish_seed_file's job.
  def _valid_seed?
    @seed = _seed_from_config || _seed_from_env || _seed_from_file
    return (not @seed.nil? and @seed.length >= MIN_SEED_LEN)
  end

  def _seed_from_config
    s = Rails.configuration.x.relay.file_store[:secret_seed]
    (s.nil? or s.empty?) ? nil : s
  end

  def _seed_from_env
    s = ENV['ZAX_SECRET_SEED']
    (s.nil? or s.empty?) ? nil : s
  end

  # Read verbatim (no strip) so an already-persisted seed is byte-identical to
  # what earlier versions established — changing it would orphan stored files.
  def _seed_from_file
    return nil unless File.exist?(_seed_path)
    s = File.read(_seed_path)
    s.empty? ? nil : s
  end

  def _ensure_secret_seed
    # A seed PRESENT in any source but too short is a fatal misconfiguration:
    # stored files are bound to it (so we must not overwrite/regenerate), yet
    # it is too weak/short to operate. Refuse to start and let the admin
    # resolve it, rather than silently clobbering critical data.
    _check_seed_source(_seed_from_config, 'config file_store[:secret_seed]')
    _check_seed_source(_seed_from_env, "ENV['ZAX_SECRET_SEED']")
    _check_seed_source(_seed_from_file, _seed_path)

    # Every PRESENT source must agree. If config/ENV and the persisted file
    # disagree we cannot know which is the authoritative long-term seed, and
    # picking wrong silently orphans data — refuse to start.
    _check_seed_consistency

    if _valid_seed?
      # A seed already exists somewhere — NEVER overwrite it.
      Rails.configuration.x.relay.file_store[:secret_seed] = @seed
      return
    end

    # Nothing established yet (fresh deploy): create the seed file ATOMICALLY
    # so concurrent workers/threads converge on one seed instead of each
    # generating its own and clobbering the file.
    @seed = _establish_seed_file
    Rails.configuration.x.relay.file_store[:secret_seed] = @seed

    unless @seed and @seed.length >= MIN_SEED_LEN
      fail ConfigError.new @controller,
        msg: 'FileManager: could not establish a valid secret_seed'
    end
  end

  # Atomic create-or-converge. Write our candidate to a unique temp file, then
  # hard-link it to secret_seed.txt: link() atomically fails with EEXIST if the
  # seed already exists, so (a) an established seed is never overwritten and
  # (b) every racing worker ends up reading the single published seed. The real
  # path only ever appears fully written, so no reader sees a partial seed.
  def _establish_seed_file
    candidate = rand_str 32
    # hex suffix (not rand_str — its base64 alphabet contains '/', unsafe in a path)
    tmp = "#{_seed_path}.#{Process.pid}.#{rand_bytes(8).unpack1('H*')}.tmp"
    File.open(tmp, File::WRONLY | File::CREAT | File::EXCL) { |f| f.write(candidate); f.flush }
    begin
      File.link(tmp, _seed_path)
    rescue Errno::EEXIST
      # another worker published first — we read theirs below and converge
    ensure
      File.delete(tmp) rescue nil
    end
    _seed_from_file
  end

  # A source that is absent (nil) is fine — fall through to the next source or
  # generate. A source that is PRESENT but shorter than MIN_SEED_LEN is fatal.
  def _check_seed_source(seed, where)
    return if seed.nil? or seed.length >= MIN_SEED_LEN
    fail ConfigError.new @controller,
      msg: "secret_seed at #{where} is #{seed.length} chars (min #{MIN_SEED_LEN}) — "\
        "refusing to start. Stored files are bound to this seed; fix or remove it by hand."
  end

  # All present seed sources (config, ENV, file) must be identical. Any
  # divergence is a fatal ambiguity: stored files are bound to exactly one
  # seed, and there is no safe way to guess which. Fail closed so no client
  # can upload against a wrong seed until an admin reconciles them.
  def _check_seed_consistency
    present = {
      'config file_store[:secret_seed]' => _seed_from_config,
      "ENV['ZAX_SECRET_SEED']"          => _seed_from_env,
      _seed_path                        => _seed_from_file,
    }.reject { |_, v| v.nil? }

    return if present.values.uniq.length <= 1 # 0 or 1 distinct value => consistent

    fail ConfigError.new @controller,
      msg: "secret_seed sources disagree (#{present.keys.join(', ')}) — refusing to "\
        "start. Stored files are bound to one seed; reconcile all sources to match."
  end

end
