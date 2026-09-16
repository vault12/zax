# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'json'

class Mailbox
  include Utils
  include Helpers::TransactionHelper

  # --- HPK and redis storage tags
  attr_reader :hpk

  # redis hash of all messages to given hpk
  def hpk_tag
    "mbx_#{@hpk}"
  end

  # redis key for specific message to hpk
  def msg_tag(b64_nonce)
    "msg_#{@hpk}_#{b64_nonce}"
  end

  # message storage token that can be inspected
  # later by sender
  def token_tag(token)
    "token_#{token.to_b64}"
  end

  # redis hash indexing every live message authored by a given sender hpk
  # Fields are the full msg_ keys, so liveness is a direct EXISTS on each.
  def msg_index_from(from_b64)
    "msg_idx_from_#{from_b64}"
  end

  # redis hash indexing declared sizes of live files authored by a given
  # sender hpk. Fields are the file tracking keys (file_<storage_name>), so
  # liveness is a direct EXISTS; values are the declared file_size. Used to
  # enforce the per-sender max_storage_bytes quota.
  def file_size_index_from(from_b64)
    "file_sz_idx_#{from_b64}"
  end

  # redish hash of all file info messages sent to/from hpk
  def file_index_to(hpk_to = @hpk)
    "file_idx_to_#{hpk_to}"
  end

  def file_index_from(hpk_from)
    "file_idx_from_#{hpk_from}"
  end

  def storage_tag(storage_name)
    "#{STORAGE_PREFIX}#{storage_name}"
  end

  def file_lock_tag(storage_id)
    "file_lock_#{storage_id.to_b64}"
  end

  # --- create Mailbox for the given HPK with options to override timeouts
  def initialize( hpk_b64, options = {})
    unless hpk_b64 and hpk_b64.length == HPK_B64
      fail HpkError.new self, msg: 'Mailbox: wrong hpk format', hpk: hpk_b64
    end

    @tmout_mbx = options[:mbx_expire] || Rails.configuration.x.relay.mailbox_timeout
    @tmout_msg = options[:msg_expire] || Rails.configuration.x.relay.message_timeout
    fail ReportError.new self, msg: 'Mailbox expire must be greater than or equal to Message expire' if @tmout_msg > @tmout_mbx

    @tmout_files = options[:files_expiration] || Rails.configuration.x.relay.file_store[:files_expiration]
    if FileManager.is_enabled? and not @tmout_files
      @tmout_files = 7.days.seconds.to_i
      logger.warn "#{WARN} Missing config setting: FileManager is enabled, yet :files_expiration is not set. Defaulting to #{@tmout_files}"
    end

    @hpk = hpk_b64
    @lastCount = nil
  end

  def timeout(kind)
    return @tmout_msg if kind == :message
    return @tmout_files if kind == :file
  end

  # number of messages for this mailbox in redis
  # value is volatile: messages can expire at any moment
  def count()
    # @lastCount may over-report just expired items
    # but they will be skipped in read_all
    return @lastCount if @lastCount
    return 0 unless rds.exists? hpk_tag
    _compact
    @lastCount = rds.hlen(hpk_tag).to_i
  end

  # Store message for this mailbox. Message sender
  # provides the nonce used in encryption which due to
  # nonce uniqueness is also used as the message id.
  def store(from, nonce, data, kind = :message, extra = {})
    _check_preconditions(from,nonce,data,kind)
    # dup before force_encoding: mutating the caller's string in place warns on a frozen/literal arg under Ruby 3.4+
    data = data.dup.force_encoding('utf-8')

    b64_nonce = nonce.to_b64
    item = {
      from: from.to_b64,        # hpk of mailbox sending this message
      nonce: b64_nonce,         # the nonce originator used for his encryption
      data: data.to_b64,        # encrypted payload
      time: Time.new.to_f,      # time message is received by relay
      kind: kind.to_s.to_b64   # type of data: message or file
    }

    # Using storage record token the sender or the recipient can check status of the message. 
    # Both hpks are recorded so check_msg_status can authorize the caller 
    storage_record = {
      hpk: @hpk,           # recipient mailbox hpk (hpk_to)
      from: from.to_b64,   # sender hpk (hpk_from)
      nonce: b64_nonce
    }
    storage_token = h2 "#{@hpk}#{b64_nonce}"

    _resetCount()

    # Reap dead index fields BEFORE the transaction so the counts asserted under
    # WATCH (in `guard` below) reflect only live entries. Reaping only removes
    # already-dead fields, so it is safe — and cheaper — to run outside the lock.
    _reap_index msg_index_from(from.to_b64)
    if kind == :file
      _reap_index file_size_index_from(from.to_b64)
      # Reap dead fields from both file index hashes: expired files leave large file_info JSON
      _reap_file_index file_index_to
      _reap_file_index file_index_from(from.to_b64)
    end

    # Reap index entries for already-expired messages before adding a new one. The mbx_ hash TTL is refreshed on every store,
    # mailbox that is written to but never read/drained accumulates dead nonce fields.
    _compact

    tmout = timeout(kind)
    file_info = nil
    storage_id = nil

    # WATCH every key the guard reads, so a concurrent store that changes any of
    # them aborts and retries this one — making the checks atomic with the write.
    watch_keys = [hpk_tag, msg_index_from(from.to_b64), msg_tag(b64_nonce)]
    watch_keys << file_size_index_from(from.to_b64) if kind == :file

    # Guarded read: runs under WATCH before MULTI and again on every retry, so the
    # caps and nonce-uniqueness are re-evaluated against fresh state. Raising here
    # aborts the store (the helper's ensure clears the WATCH).
    guard = Proc.new do
      # Reject nonce reuse by wrong clients. Correct clients always generate fresh random nonces and never see this.
      if rds.exists? msg_tag(b64_nonce)
        fail ReportError.new self, msg: "mailbox: nonce reuse — message #{b64_nonce} already queued for #{dumpHex @hpk.from_b64}"
      end
      # Enforce the per-sender hard cap: reject once this originator already keeps max_messages live messages
      _assert_sender_under_msg_cap(from)
      # Enforce the per-recipient hard cap
      _assert_recipient_under_msg_cap
      # Per-sender byte quota: reject a new file if the declared sizes of this hpk's files reach max_storage_bytes
      _assert_sender_under_byte_quota(from, extra[:file_size]) if kind == :file
    end

    res = runRedisTransaction(watch_keys, @hpk, 'store', guard) do |_guard, rds_transaction|
      # by default everytihing in mailbox will expire in 3 days
      # files will expire in 7 days

      # store message itself on the msg_hpk_nonce tag
      rds_transaction.set(msg_tag(b64_nonce), item.to_json)
      rds_transaction.expire(msg_tag(b64_nonce), tmout)

      # mbx_hpk is used as index hash of all messages to @hpk
      rds_transaction.hset(hpk_tag, b64_nonce, (Time.new + tmout).to_s)
      rds_transaction.expire(hpk_tag, tmout)

      # index this message under its sender for the per-sender cap
      from_idx = msg_index_from(from.to_b64)
      rds_transaction.hset(from_idx, msg_tag(b64_nonce), (Time.new + tmout).to_s)
      rds_transaction.expire(from_idx, tmout)

      # store unique storage token for that item
      # visible to sender (hpk_from) when stored or deleted by @hpk
      rds_transaction.set(token_tag(storage_token), storage_record.to_json)
      rds_transaction.expire(token_tag(storage_token), tmout)

      # :file message is same as other messages handled by relays,
      # which additionally passes to hpk_to 'uploadID' that it can
      # use to issue file commands to relay.
      if kind == :file
        # Relay can easily re-create storage_id from uploadID (kept
        # only by client) and FileManeger @seed, but relay can not
        # restore uploadID from various saved storage_id's
        storage_id = extra[:storage_id]
        storage_name = extra[:storage_name]
        file_info = {
          status: :START,
          parts: [],
          file_size: extra[:file_size],
          bytes_stored: 0,
          hpk_to: @hpk,
          hpk_from: extra[:hpk_from].to_b64,
          total_chunks: 0 # Nothing received yet
        }

        # file_index to/from hpk is used as index hash of all files
        save_file_info(file_info, extra[:hpk_from], storage_id, rds_transaction) if file_info and kind == :file
        save_file_tracking_info(storage_name, tmout, rds_transaction)

        # index the declared size under the sender for the per-hpk storage
        # quota. The field is the file's tracking key, so once the file is
        # deleted or expires the field goes dead and is reaped at next check.
        sz_idx = file_size_index_from(extra[:hpk_from].to_b64)
        rds_transaction.hset(sz_idx, storage_tag(storage_name), extra[:file_size].to_i)
        rds_transaction.expire(sz_idx, tmout)
      end
    end

    return { opResult: res, storage_token: storage_token }
  end

  # Is message for given storage token still in redis?
  def check_msg_status(storage_token)
    tag = token_tag storage_token
    storage_item = parse rds.get tag
    return "-2" unless storage_item # following redis TTL codes

    # only the message's own recipient (hpk_to) or sender (hpk_from) may probe its status. 
    # For any other caller return the same "-2" a missing record yields
    hpk_to   = storage_item[:hpk].to_b64
    hpk_from = storage_item[:from]&.to_b64
    return "-2" unless @hpk == hpk_to || @hpk == hpk_from

    mbx = Mailbox.new hpk_to
    ttl = rds.ttl mbx.msg_tag storage_item[:nonce].to_b64
    return "#{ttl}"
  end

  def file_status_from_uid(uploadID, file_manager)
    file_status file_manager.storage_from_upload(uploadID).to_b64
  end

  def file_status(storage_id_b64)
    # File might be sent by @hpk or from @hpk - checking both
    res = rds.hget file_index_to, storage_id_b64
    res = rds.hget file_index_from(@hpk), storage_id_b64 unless res
    res = res ? JSON.parse(res, symbolize_names: true) : nil

    # Stale entry for an expired/pruned file: chunks and tracking key are gone 
    # but the index field remains. Drop it from both sides and report NOT_FOUND
    if res and not rds.exists? storage_tag(FileManager.storage_name_from_id(storage_id_b64.from_b64))
      rds.hdel file_index_to(res[:hpk_to]), storage_id_b64
      rds.hdel file_index_from(res[:hpk_from]), storage_id_b64
      res = nil
    end

    res = { status: :NOT_FOUND, bytes_stored: 0, parts: [] } unless res
    return res
  end

  def save_file_info(file_info, hpk_from, storage_id, rds_transaction)
    file_info_js = file_info.to_json
    tmout = timeout(:file)

    # file_index to/from hpk is used as index hash of all files
    rds_transaction.hset(file_index_to, storage_id.to_b64, file_info_js)
    rds_transaction.expire(file_index_to, tmout)

    fidx_from = file_index_from(hpk_from.to_b64)
    rds_transaction.hset(fidx_from, storage_id.to_b64, file_info_js)
    rds_transaction.expire(fidx_from, tmout)
  end

  def save_file_tracking_info(storage_name, tmout, rds_transaction)
    # global index is used by workers to clear out expired files
    rds_transaction.sadd(ZAX_GLOBAL_FILES, storage_tag(storage_name))

    # When storage tag expires but still present
    # in persistent GLOBAL set, the recurring sweep (FilesCheck) will delete
    # the file and remove it from GLOBAL.
    # The tracking value carries the upload lifecycle (START -> COMPLETE, see
    # mark_file_complete) so the sweep can reap stalled uploads early without
    # touching finished files awaiting download.
    rds_transaction.set(storage_tag(storage_name), 'START')
    rds_transaction.expire(storage_tag(storage_name), tmout)
  end

  # Flip the tracking value once the last chunk landed: a COMPLETE file is
  # exempt from the stalled-upload sweep and lives out its full expiration
  # awaiting download. KEEPTTL preserves the expiry set at startFileUpload.
  def mark_file_complete(storage_name, rds_transaction)
    rds_transaction.set(storage_tag(storage_name), 'COMPLETE', keepttl: true)
  end

  # Remove a file's index entries under the SAME watched lock that uploadFileChunk holds. Touching file_lock_tag inside this
  # transaction aborts a concurrent upload's WATCH so it retries; without this, the upload's MULTI would resurrect the file_info 
  # we just deleted. The to-index is keyed by the RECIPIENT (hpk_to), so it must be passed explicitly
  def delete_file_info(hpk_from, hpk_to, storage_id)
    lock = file_lock_tag(storage_id)
    runRedisTransaction(lock, nil, 'delete file_info') do |_read, rds_transaction|
      # Modify the watched key so a concurrent uploadFileChunk aborts+retries
      rds_transaction.set lock, rand_str(24), **{ ex: 2 }
      rds_transaction.hdel(file_index_to(hpk_to.to_b64), storage_id.to_b64)
      rds_transaction.hdel(file_index_from(hpk_from.to_b64), storage_id.to_b64)
      rds_transaction.del lock
    end
  end

  # read all or subset of messages in mailbox
  def read_all(start = 0, size = -1)
    a = []
    size = count - start if size == -1
    result = rds.exists? hpk_tag
    return a unless result and size > 0

    # read all nonces as list
    nonces = rds.hkeys hpk_tag
    limit = start+size <= nonces.length ? start + size : nonces.length

    # read all messages requested in atomic transaction
    res = runRedisTransaction(hpk_tag, @hpk, 'read_all') do |_file_info, rds_transaction|
      for i in (start...limit)
        rds_transaction.get msg_tag nonces[i]
      end
    end

    # decode each item from base64 and check for null values
    # left by expired messages
    res.each do |item|
      next unless item
      msg = parse item
      yield msg if block_given?
      a.push msg
    end
    return a
  end

  def parse(item)
    return nil if item.nil?
    msg = JSON.parse(item.to_s)
    return Hash[msg.map { |k, v| [ k.to_sym, k != "time" ? v.from_b64.force_encoding('utf-8') : v ] }]
  end

  def _delete_item(nonce, rds_transaction)
    rds_transaction.del msg_tag nonce
    rds_transaction.hdel hpk_tag, nonce
    # storage token record lives at token_<b64> 
    rds_transaction.del token_tag(h2 "#{@hpk}#{nonce}")
  end

  # Delete one message by nonce
  def delete(nonce)
    _resetCount()
    runRedisTransaction(hpk_tag, @hpk, 'delete') do |_file_info, rds_transaction|
      _delete_item nonce, rds_transaction
      # Log the nonce as-is - base64 
      logger.info "#{INFO} #{RED}deleting #{GREEN}#{dumpHex nonce}#{ENDCLR} in mbx #{MAGENTA}#{dumpHex @hpk.from_b64}#{ENDCLR}"
    end
  end

  # Delete list of messages by list of nonces
  def delete_list(nonce_list)
    _resetCount()
    runRedisTransaction(hpk_tag, @hpk, 'delete list') do |_file_info, rds_transaction|
      nonce_list.each do |nonce|
        _delete_item nonce, rds_transaction
        # Log the nonce as-is - base64
        logger.info "#{INFO} #{RED}deleting #{GREEN}#{dumpHex nonce}#{ENDCLR} in mbx #{MAGENTA}#{dumpHex @hpk.from_b64}#{ENDCLR}"
      end
    end
  end

  private

  def _check_preconditions(from, nonce, data, kind)
    unless data and from and from.length == HPK_LEN and
      (kind == :message or kind == :file)
      fail ReportError.new self, msg: 'mailbox.store() : wrong params'
    end

    # The stored-message nonce becomes the message id (msg_ key, index fields, storage token) — enforce the protocol size
    unless nonce and nonce.length == NONCE_LEN
      fail ReportError.new self, msg: "mailbox.store() : nonce must be #{NONCE_LEN} bytes"
    end

    if kind == :file and not FileManager.is_enabled?
      fail ReportError.new self, msg: 'Mailbox receives file command while FileManager is not enabled'
    end
  end

  # messages expire independently of hashed index. we update index
  # and remove nonces for messages that already expired
  def _compact
    nonces = rds.hkeys hpk_tag
    return if nonces.empty?

    # Check liveness of every nonce in a single pipelined round-trip rather than one blocking EXISTS per nonce
    present = rds.pipelined { |pipe| nonces.each { |n| pipe.exists msg_tag(n) } }
    
    # select all nonces that no longer have corresponding message stored
    toDel = nonces.each_index.select { |i| present[i].to_i == 0 }.map { |i| nonces[i] }

    # delete all these nonces from hash index
    unless toDel.empty?
      _resetCount()
      runRedisTransaction(hpk_tag, @hpk, 'compact') do |_file_info, rds_transaction|
        toDel.each { |n| rds_transaction.hdel hpk_tag, n }
      end
    end
  end

  def _resetCount()
    @lastCount = nil
  end

  # Reject the write when this sender already keeps max_messages live messages across all mailboxes. 
  # Read-only: the sender index is reaped by the caller BEFORE the transaction this assertion runs 
  # inside the WATCHed guard so it re-evaluates on each retry and is atomic with the write
  def _assert_sender_under_msg_cap(from)
    max = Rails.configuration.x.relay.max_messages
    return unless max

    idx = msg_index_from(from.to_b64)
    if rds.hlen(idx).to_i >= max
      fail ReportError.new self, reason: 'SenderCap', msg: "mailbox: sender #{dumpHex from} at max_messages (#{max})"
    end
  end

  # Reject the write when this recipient mailbox already holds max_messages live messages 
  # Read-only; runs inside the WATCHed guard, and hpk_tag is already in the watch set so the check is atomic with the write.
  # hpk_tag is compacted (dead fields reaped) before the transaction, so hlen is live.
  def _assert_recipient_under_msg_cap
    max = Rails.configuration.x.relay.max_messages
    return unless max

    if rds.hlen(hpk_tag).to_i >= max
      fail MailboxFullError.new self, msg: "mailbox: destination #{dumpHex @hpk.from_b64} full (#{max} messages)"
    end
  end

  # Reject a new file when the declared sizes of this sender's live files plus the new file would exceed max_storage_bytes. 
  # Read-only, like the message-cap assertion: reaped by the caller, run inside the WATCHed guard.
  def _assert_sender_under_byte_quota(from, file_size)
    max = Rails.configuration.x.relay.file_store[:max_storage_bytes]
    return unless max and max > 0

    idx = file_size_index_from(from.to_b64)
    used = rds.hvals(idx).sum(&:to_i)
    if used + file_size.to_i > max
      # QuotaExceededError deliberately names the reason to the sender
      fail QuotaExceededError.new self, msg:
        "mailbox: sender #{dumpHex from} over max_storage_bytes: #{used} stored + #{file_size} requested > #{max}"
    end
  end

  # Reap fields of a file_idx_* hash whose file has expired.
  # Fields are storage_id b64; a file is live iff its tracking key file_<storage_name> exists
  def _reap_file_index(idx)
    fields = rds.hkeys idx
    return if fields.empty?
    present = rds.pipelined do |pipe|
      fields.each { |f| pipe.exists storage_tag(FileManager.storage_name_from_id(f.from_b64)) }
    end
    dead = fields.each_index.select { |i| present[i].to_i == 0 }.map { |i| fields[i] }
    rds.hdel(idx, *dead) unless dead.empty?
  end

  # Remove index fields whose message key no longer exists. Fields ARE the full
  # msg_ keys, so liveness is a direct EXISTS, batched into one pipelined round-trip.
  def _reap_index(idx)
    fields = rds.hkeys idx
    return if fields.empty?
    present = rds.pipelined { |pipe| fields.each { |f| pipe.exists f } }
    dead = fields.each_index.select { |i| present[i].to_i == 0 }.map { |i| fields[i] }
    rds.hdel(idx, *dead) unless dead.empty?
  end

end
