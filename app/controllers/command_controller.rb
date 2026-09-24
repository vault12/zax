# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class CommandController < ApplicationController
  public
  include Helpers::TransactionHelper
  attr_reader :body

  ALL_COMMANDS = %w(
    count upload download delete messageStatus
    startFileUpload fileStatus deleteFile
    uploadFileChunk downloadFileChunk
    getEntropy)

  def process_cmd
    reportCommonErrors("process command error => ") do
      @body_preamble = request.body.read COMMAND_BODY_PREAMBLE
      lines = check_body_preamble_command_lines @body_preamble
      @hpk = _get_hpk lines[0]
      # Stateless nonce validation only; the replay-cache WRITE is deferred to after decrypt (below) so an unauthenticated request writes nothing.
      nonce = _validate_nonce lines[1].from_b64

      @body = request.body.read MAX_COMMAND_BODY
      lines = check_body_command_lines @body
      ctext = lines[0].from_b64
      load_keys

      data = decrypt_data nonce, ctext
      # The box opened with this hpk's session key, so the sender is who the
      # preamble says. Up to this line the hpk is anyone's claim, and a
      # rejection before it is counted without a sender (report_rejection).
      @sender = @hpk
      # The top-level JSON TYPE is attacker-controlled too: JSON.parse returns
      # whatever scalar or array the box carried, and data[:cmd] on a non-Hash
      # raises TypeError/NoMethodError — a 500 and a client-triggerable Sentry
      # event instead of a 400. Reject non-object packets before touching data.
      unless data.is_a?(Hash)
        fail BodyError.new self, msg: 'command_controller: command packet must be a JSON object'
      end
      # Known command names only: an attacker-chosen string must not become
      # a log tag or a Sentry attribute
      @cmd = data[:cmd] if ALL_COMMANDS.include?(data[:cmd])
      # Budget is charged only after successful decryption, thus hpk session keys are verified first
      check_rate_limit
      # Record the nonce for replay protection
      _check_nonce_unique nonce
      data[:ctext] = lines[1] if lines[1] # extra line on uploadFileChunk
      check_command data
      mailbox = Mailbox.new @hpk.to_b64
      rsp_nonce = _make_nonce

      # === Process command ===
      logger.info "#{CMD}#{GREEN}#{@cmd}#{ENDCLR}"
      case @cmd

      # ===   Messaging commands ===
      when 'upload'     # === ⌘ Upload ===
        res = Commands::UploadCmd.new(@hpk,mailbox).process(data)[:storage_token].to_b64
        render plain: "#{res}", status: :ok

      when 'count'      # === ⌘ Count ===
        render_encrypted rsp_nonce, Commands::CountCmd.new(@hpk,mailbox).process(data)

      when 'download'   # === ⌘ Download ===
        render_encrypted rsp_nonce, Commands::DownloadCmd.new(@hpk,mailbox).process(data)

      when 'messageStatus' # === ⌘ Message Status ===
        ttl = Commands::StatusCmd.new(@hpk,mailbox).process(data)
        render plain: "#{ttl}", status: :ok

      when 'delete'     # === ⌘ Delete ===
        # Empty/malformed delete payloads are already rejected in check_command
        res = Commands::DeleteCmd.new(@hpk,mailbox).process(data)
        render plain: "#{res}", status: :ok

      # ===   File commands ===
      when 'startFileUpload'  # === ⌘ startFileUpload ===
        # full error check in check_errors
        return unless check_filemanager
        payload = Commands::StartFileUploadCmd.new(@hpk,mailbox,self).process(data)
        render_encrypted rsp_nonce,payload

      when 'fileStatus'       # === ⌘ fileStatus ===
        return unless check_filemanager
        file_info = Commands::FileStatusCmd.new(@hpk,mailbox,self).process(data)
        render_encrypted rsp_nonce,file_info

      when 'uploadFileChunk'  # === ⌘ uploadFileChunk ===
        return unless check_filemanager
        payload = Commands::UploadFileCmd.new(@hpk,mailbox,self).process(data)
        payload ||= { status: :NOT_FOUND }
        render_encrypted rsp_nonce, payload

      when 'downloadFileChunk'  # === ⌘ downloadFileChunk ===
        return unless check_filemanager
        payload, file = Commands::DownloadFileCmd.new(@hpk,mailbox,self).process(data)
        payload ||= { status: :NOT_FOUND }
        render_encrypted rsp_nonce, payload, file

      when 'deleteFile'         # === ⌘ deleteFile ===
        return unless check_filemanager
        payload = Commands::DeleteFileCmd.new(@hpk,mailbox,self).process(data)
        render_encrypted rsp_nonce, payload

      # === Misc commands ===
      when 'getEntropy'         # === ⌘ getEntropy ===
        payload = { entropy: rand_bytes(ENTROPY_SIZE).to_b64 } # Fixed payload, no client size
        render plain: payload.to_json.to_b64, status: :ok
      end
    end
  end


  # === Private helpers ===
  private

  # Fixed-window token bucket per sender hpk: the window opens at
  # the hpk's first command and allows max requests until it expires, when a
  # fresh budget opens. SET NX creates the window with its TTL before INCR
  # (so a crash between the two can't leave a permanent counter), and the
  # TTL re-arm below covers the other hole: the window expiring between
  # SET NX and INCR, which would resurrect the counter without a TTL.
  def check_rate_limit
    limit = Rails.configuration.x.relay.max_requests_per_seconds
    return unless limit
    max, window = limit

    key = "rate_#{@hpk.to_b64}"
    rds.set(key, 0, ex: window, nx: true)
    count = rds.incr(key)
    rds.expire(key, window) if rds.ttl(key) < 0
    if count.to_i > max
      # Redis TTL is whole seconds; +1 so a client sleeping exactly Retry-After
      # wakes inside the fresh window, not at the tail of the exhausted one.
      # A non-positive TTL means the window expired since INCR (the re-arm above
      # leaves no persistent counter behind), so a fresh budget is already open —
      # advertise the minimum wait instead of a full idle window.
      ttl = rds.ttl(key)
      fail RateLimitError.new self,
        msg: "rate limit: hpk #{dumpHex @hpk} over #{max} requests per #{window}s window",
        retry_after: ttl.positive? ? [ttl + 1, window].min : 1
    end
  end

  def load_keys
    logger.info "#{INFO_GOOD} Reading client session key for hpk #{MAGENTA}#{dumpHex @hpk}#{ENDCLR}"
    @session_key = Rails.cache.read("session_key_#{@hpk}")
    @client_key = Rails.cache.read("client_key_#{@hpk}")
    fail HpkKeys.new(self, {hpk: @hpk, msg: 'No cached session key'}) unless @session_key
    fail HpkKeys.new(self, {hpk: @hpk, msg: 'No cached client key'}) unless @client_key
  end

  def check_body_preamble_command_lines(body)
    lines = check_body_break_lines body
    pl = lines ? lines.count : 0
    unless lines && lines.count == 2
      fail BodyError.new self, msg: "wrong number of lines in preamble command body, #{pl} line(s)", lines: pl
    end
    unless lines && lines.count == 2 &&
           lines[0].length == TOKEN_B64 &&
           lines[1].length == NONCE_B64
      fail BodyError.new self, msg: "process_cmd malformed preamble command body, #{pl} line(s)", lines: pl
    end
    lines
  end

  def check_body_command_lines(body)
    lines = check_body_break_lines body
    pl = lines ? lines.count : 0
    unless lines && (lines.count == 1 or lines.count == 2)
      fail BodyError.new self, msg: "wrong number of lines in command body, #{pl} line(s)", lines: pl
    end
    lines
  end

  def check_body_break_lines(body)
    fail BodyError.new self, msg: 'No request body' if body.nil? || body.empty?
    nl = body.include?("\r\n") ? "\r\n" : "\n"
    body.split nl
  end

  def decrypt_data(nonce, ctext)
    box = RbNaCl::Box.new(@client_key, @session_key)
    d = JSON.parse box.decrypt(nonce, ctext).force_encoding('utf-8'),symbolize_names: true
  end

  def encrypt_data(nonce, data)
    box = RbNaCl::Box.new(@client_key, @session_key)
    box.encrypt(nonce, data.to_json).to_b64
  end

  def render_encrypted(nonce,data,extra_line = nil)
    enc_payload = encrypt_data(nonce, data)
    enc_payload +="\r\n#{extra_line}" if extra_line
    render plain: "#{nonce.to_b64}\r\n#{enc_payload}", status: :ok
  end

  def check_command(data)
    all = ALL_COMMANDS

    fail ReportError.new self, msg: 'command_controller: missing command' unless data[:cmd]
    fail ReportError.new self, msg: "command_controller: unknown command #{data[:cmd]}" unless all.include? data[:cmd]

    # === Message commands error checks
    # Field TYPES are attacker-controlled after JSON.parse — every field is
    # asserted before use so malformed input yields 400, never a
    # NoMethodError/TypeError 500
    if data[:cmd] == 'upload'
      fail ReportError.new self, msg: 'command_controller: no destination HPK in upload' unless data[:to].is_a?(String)
      hpk_dec = data[:to].from_b64
      _check_hpk hpk_dec
      payload = data[:payload]
      fail ReportError.new self, msg: 'command_controller: no payload in upload' unless payload
      # payload is either a plain-text String or {ctext:, nonce:} of Strings
      unless payload.is_a?(String) or
        (payload.is_a?(Hash) and payload[:ctext].is_a?(String) and
          (payload[:nonce].nil? or payload[:nonce].is_a?(String)))
        fail ReportError.new self, msg: 'upload: payload must be a String or {ctext:, nonce:} of Strings'
      end
    end

    if data[:cmd] == 'messageStatus'
      fail ReportError.new self, msg: 'command_controller: bad/missing storage token in messageStatus' unless data[:token].is_a?(String) and data[:token].length == TOKEN_B64
    end

    if data[:cmd] == 'download'
      start = data[:start] || 0
      count = data[:count] || 0
      fail ReportError.new self, msg: 'download: start must be a non-negative integer' unless start.is_a?(Integer) and start >= 0
      fail ReportError.new self, msg: 'download: count must be a non-negative integer' unless count.is_a?(Integer) and count >= 0
    end

    if data[:cmd] == 'delete'
      payload = data[:payload]
      fail ReportError.new self, msg: 'command_controller: no ids to delete' unless payload
      fail ReportError.new self, msg: 'delete: payload must be an array of nonce strings' unless payload.is_a?(Array) and payload.all? { |id| id.is_a?(String) }
      fail ReportError.new self, msg: 'command_controller: too many ids to delete' if payload.length > MAX_ITEMS
    end

    # === File commands error checks
    if data[:cmd] == 'startFileUpload'
      fail ReportError.new self, msg: 'startFileUpload: hpk :to required' unless data[:to].is_a?(String) and data[:to].length >= HPK_B64
      fail ReportError.new self, msg: 'startFileUpload: file_size required' unless data[:file_size]
      fail ReportError.new self, msg: 'startFileUpload: file_size must be a positive integer' unless data[:file_size].is_a?(Integer) && data[:file_size] > 0
      max_file_size = Rails.configuration.x.relay.file_store[:max_file_size]
      fail FileSizeLimitError.new self, msg: "startFileUpload: Upload file size is over the #{max_file_size} byte limit" if max_file_size and data[:file_size] > max_file_size
      fail ReportError.new self, msg: 'startFileUpload: Metadata missing' unless data[:metadata].is_a?(Hash)
      fail ReportError.new self, msg: 'startFileUpload: Metadata ctext missing' unless data[:metadata][:ctext].is_a?(String)
      fail ReportError.new self, msg: 'startFileUpload: Metadata nonce missing' unless data[:metadata][:nonce].is_a?(String) and data[:metadata][:nonce].length >= NONCE_B64
    end

    if data[:cmd] == 'fileStatus'
      fail ReportError.new self, msg: "fileStatus: missing uploadID" unless data[:uploadID].is_a?(String)
    end

    if data[:cmd] == 'uploadFileChunk'
      %i(uploadID part nonce ctext).each do |f|
        fail ReportError.new self, msg: "uploadFileChunk: missing #{f}" unless data[f]
      end
      %i(uploadID nonce ctext).each do |f|
        fail ReportError.new self, msg: "uploadFileChunk: #{f} must be a string" unless data[f].is_a?(String)
      end
      fail ReportError.new self, msg: "uploadFileChunk: part must be a non-negative integer" unless data[:part].is_a?(Integer) && data[:part] >= 0
    end

     if data[:cmd] == 'downloadFileChunk'
      %i(uploadID part).each do |f|
        fail ReportError.new self, msg: "downloadFileChunk: missing #{f}" unless data[f]
      end
      fail ReportError.new self, msg: "downloadFileChunk: uploadID must be a string" unless data[:uploadID].is_a?(String)
      fail ReportError.new self, msg: "downloadFileChunk: part must be a non-negative integer" unless data[:part].is_a?(Integer) && data[:part] >= 0
     end

    if data[:cmd] == 'deleteFile'
      fail ReportError.new self, msg: "missing uploadID" unless data[:uploadID].is_a?(String)
    end

    # getEntropy takes no parameters: the response is a fixed ENTROPY_SIZE
    # payload and any legacy :size field is ignored

    return data
  end

  # A relay that runs without a file store refuses file commands with 405,
  # answered here rather than through reportCommonErrors, so the rejection
  # names itself: a limit of this relay's own configuration, not a client
  # mistake.
  def check_filemanager
    return true if FileManager.is_enabled?
    @rejection = 'FilesDisabled'
    head :method_not_allowed
    false
  end

end
