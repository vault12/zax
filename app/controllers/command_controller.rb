# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class CommandController < ApplicationController
  public
  attr_reader :body

  def process_cmd
    @body_preamble = request.body.read COMMAND_BODY_PREAMBLE
    lines = check_body_preamble_command_lines @body_preamble
    @hpk = _get_hpk lines[0]
    nonce = _check_nonce b64dec lines[1]

    @body = request.body.read MAX_COMMAND_BODY
    lines = check_body_command_lines @body
    ctext = b64dec lines[0]
    load_keys
    data = decrypt_data nonce, ctext
    mailbox = Mailbox.new @hpk
    rsp_nonce = _make_nonce
    # === Process command ===
    case data[:cmd]
    when 'upload'
      hpkto = b64dec data[:to]

      # Nonce is included for A->B private messages
      msg_nonce = b64dec data[:payload]['nonce'] if data[:payload]['nonce']

      # Make one if payload is a plain text message
      msg_nonce = _make_nonce unless msg_nonce
      mbx = Mailbox.new hpkto

      # Ctext of private messages or plain text payload
      msg = data[:payload]['ctext'] || data[:payload]

      res = mbx.store @hpk, msg_nonce, msg
      logger.info "#{INFO_GOOD} stored item #{dumpHex msg_nonce} mbx '#{dumpHex @hpk}' => '#{dumpHex hpkto}'"
      render text: "#{b64enc res[:storage_token]}", status: :ok

    when 'count'
      enc_nonce = b64enc rsp_nonce
      cnt = mailbox.count
      enc_data = encrypt_data rsp_nonce, cnt
      logger.info "#{INFO} #{cnt} items in mbx #{dumpHex @hpk}"
      render text: "#{enc_nonce}\r\n#{enc_data}", status: :ok

    when 'download'
      count = data[:count] || mailbox.count > MAX_ITEMS ? MAX_ITEMS : mailbox.count
      start = data[:start] || 0
      fail ReportError.new self, msg: 'Bad download start position' unless start >= 0 || start < mailbox.count
      payload = mailbox.read_all start, count
      payload = process_payload(payload)
      enc_nonce = b64enc rsp_nonce
      enc_payload = encrypt_data rsp_nonce, payload
      logger.info "#{INFO_GOOD} downloading #{count} mbx '#{dumpHex @hpk}'"
      render text: "#{enc_nonce}\r\n#{enc_payload}", status: :ok

    when 'message_status'
      storage_token = b64dec data[:token]
      ttl = mailbox.check_msg_status storage_token
      render text: "#{ttl}", status: :ok

    when 'delete'
      render nothing: true, status: :ok unless data[:payload]
      mailbox.delete_list data[:payload]
      logger.info "#{INFO_GOOD} deleting from mbx '#{dumpHex @hpk}'"
      render text: "#{mailbox.count}", status: :ok
    end

    # === Error handling ===
    rescue RbNaCl::CryptoError => e
      ZAXError.new(self).NaCl_error e
    rescue ZAXError => e
      e.http_fail
    rescue => e
      ZAXError.new(self).report "process_cmd error",e
  end

  # === Private helpers ===
  private

  def load_keys
    logger.info "#{INFO_GOOD} Reading client session key for hpk #{dumpHex @hpk}"
    @session_key = Rails.cache.read("session_key_#{@hpk}")
    @client_key = Rails.cache.read("client_key_#{@hpk}")
    fail HPK_keys.new(self, {hpk: @hpk, msg: 'No cached session key'}) unless @session_key
    fail HPK_keys.new(self, {hpk: @hpk, msg: 'No cached client key'}) unless @client_key
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
    unless lines && lines.count == 1
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
    d = JSON.parse box.decrypt(nonce, ctext)
    d = d.reduce({}) { |h, (k, v)| h[k.to_sym] = v; h }
    check_command d
  end

  def encrypt_data(nonce, data)
    box = RbNaCl::Box.new(@client_key, @session_key)
    b64enc box.encrypt(nonce, data.to_json)
  end

  def rand_str(min, size)
    (b64enc rand_bytes min + rand(size)).delete('=')
  end

  def check_command(data)
    all = %w(count upload download delete message_status)

    fail ReportError.new self, msg: 'command_controller: missing command' unless data[:cmd]
    fail ReportError.new self, msg: "command_controller: unknown command #{data[:cmd]}" unless all.include? data[:cmd]

    if data[:cmd] == 'upload'
      fail ReportError.new self, msg: 'command_controller: no destination HPK in upload' unless data[:to]
      hpk_dec = b64dec data[:to]
      _check_hpk hpk_dec
      fail ReportError.new self, msg: 'command_controller: no payload in upload' unless data[:payload]
    end

    if data[:cmd] == 'message_status'
      fail ReportError.new self, msg: 'command_controller: bad/missing storage token in message_status' unless data[:token] and data[:token].length == TOKEN_B64
    end

    if data[:cmd] == 'delete'
      fail ReportError.new self, msg: 'command_controller: no ids to delete' unless data[:payload]
    end

    data
  end

  def process_payload(messages)
    payload_ary = []
    messages.each do |message|
      payload = {}
      payload[:data] = message[:data]
      payload[:time] = message[:time]
      payload[:from] = b64enc message[:from]
      payload[:nonce] = b64enc message[:nonce]
      payload_ary.push payload
    end
    payload_ary
  end

end
