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
      nonce = _check_nonce lines[1].from_b64

      @body = request.body.read MAX_COMMAND_BODY
      lines = check_body_command_lines @body
      ctext = lines[0].from_b64
      load_keys

      data = decrypt_data nonce, ctext
      data[:ctext] = lines[1] if lines[1] # extra line on uploadFileChunk
      check_command data
      mailbox = Mailbox.new @hpk.to_b64
      rsp_nonce = _make_nonce
      @cmd = data[:cmd]

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
        render nothing: true, status: :ok unless data[:payload]
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
        payload = { entropy: rand_bytes(data[:size]).to_b64 }
        render plain: payload.to_json.to_b64, status: :ok
      end
    end
  end


  # === Private helpers ===
  private

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
    if data[:cmd] == 'upload'
      fail ReportError.new self, msg: 'command_controller: no destination HPK in upload' unless data[:to]
      hpk_dec = data[:to].from_b64
      _check_hpk hpk_dec
      fail ReportError.new self, msg: 'command_controller: no payload in upload' unless data[:payload]
    end

    if data[:cmd] == 'messageStatus'
      fail ReportError.new self, msg: 'command_controller: bad/missing storage token in messageStatus' unless data[:token] and data[:token].length == TOKEN_B64
    end

    if data[:cmd] == 'delete'
      fail ReportError.new self, msg: 'command_controller: no ids to delete' unless data[:payload]
    end

    # === File commands error checks
    if data[:cmd] == 'startFileUpload'
      fail ReportError.new self, msg: 'startFileUpload: hpk :to required' unless data[:to] and data[:to].length >= HPK_B64
      fail ReportError.new self, msg: 'startFileUpload: Upload file size is over 1Gb limit' unless data[:file_size] and data[:file_size] < 1*1024*1024*1024 # 1 Gb as sanity limit
      fail ReportError.new self, msg: 'startFileUpload: Metadata missing' unless data[:metadata]
      fail ReportError.new self, msg: 'startFileUpload: Metadata ctext missing' unless data[:metadata][:ctext]
      fail ReportError.new self, msg: 'startFileUpload: Metadata nonce missing' unless data[:metadata][:nonce] and data[:metadata][:nonce].length >= NONCE_B64
    end

    if data[:cmd] == 'fileStatus'
      fail ReportError.new self, msg: "fileStatus: missing uploadID" unless data[:uploadID]
    end

    if data[:cmd] == 'uploadFileChunk'
      %i(uploadID part nonce ctext).each do |f|
        fail ReportError.new self, msg: "uploadFileChunk: missing #{f}" unless data[f]
      end
    end

     if data[:cmd] == 'downloadFileChunk'
      %i(uploadID part).each do |f|
        fail ReportError.new self, msg: "downloadFileChunk: missing #{f}" unless data[f]
      end
     end

    if data[:cmd] == 'deleteFile'
      fail ReportError.new self, msg: "missing uploadID" unless data[:uploadID]
    end

    if data[:getEntropy] == 'getEntropy'
      max_size = Rails.configuration.x.relay.file_store[:max_chunk_size]
      fail ReportError.new self, msg: "getEntropy: missing size" unless data[:size]
      fail ReportError.new self, msg: "getEntropy: Request for #{data[:size]} while max_size is set to #{max_size}" if data[:size]>max_size
    end

    return data
  end

  def check_filemanager
    head :method_not_allowed unless FileManager.is_enabled?
    return FileManager.is_enabled?
  end

end
