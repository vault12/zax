require 'mailbox'
class CommandController < ApplicationController
  public

  def process_cmd
    @body_preamble = request.body.read COMMAND_BODY_PREAMBLE
    lines = _check_body_preamble_command_lines @body_preamble
    @hpk = _get_hpk lines[0]
    nonce = _check_nonce b64dec lines[1]

    @body = request.body.read COMMAND_BODY
    lines = _check_body_command_lines @body
    ctext = b64dec lines[0]
    _load_keys
    data = _decrypt_data nonce, ctext
    mailbox = Mailbox.new @hpk
    rsp_nonce = _make_nonce
    # === Process command ===
    case data[:cmd]
    when 'upload'
      hpkto = b64dec data[:to]
      mbx = Mailbox.new hpkto
      mbx.store @hpk, rsp_nonce, data[:payload]
      render nothing: true, status: :ok

    when 'count'
      data = {}
      data[:count] = mailbox.count
      enc_nonce = b64enc rsp_nonce
      enc_data = _encrypt_data rsp_nonce, data
      render text: "#{enc_nonce}\r\n#{enc_data}", status: :ok

    when 'download'
      count = mailbox.count > MAX_ITEMS ? MAX_ITEMS : mailbox.count
      start = data[:start] || 0
      fail 'Bad download start position' unless start >= 0 || start < mailbox.count
      payload = mailbox.read_all start, count
      payload = _process_payload(payload)
      enc_nonce = b64enc rsp_nonce
      enc_payload = _encrypt_data rsp_nonce, payload
      render text: "#{enc_nonce}\r\n#{enc_payload}", status: :ok

    when 'delete'
      for id in data[:payload]
        mailbox.delete_by_id id
      end
      # TODO: respond with encrypted count (same as cmd='count')
      render nothing: true, status: :ok
    end
    # === Error handling ===
  rescue RbNaCl::CryptoError => e
    _report_NaCl_error e
  rescue ZAXError => e
    e.http_fail
  rescue => e
    _report_error e
  end

  private

  def _load_keys
    logger.info "#{INFO_GOOD} Reading client session key for hpk #{b64enc @hpk}"
    @session_key = Rails.cache.read("session_key_#{@hpk}")
    @client_key = Rails.cache.read("client_key_#{@hpk}")
    fail HPK_keys.new(self, @hpk), 'No cached session key' unless @session_key
    fail HPK_keys.new(self, @hpk), 'No cached client key'  unless @client_key
  end

  def _check_body_preamble_command_lines(body)
    lines = _check_body_break_lines body
    unless lines && lines.count == 2
      fail "wrong number of lines in preamble command body, #{lines ? lines.count : 0} lines"
    end
    unless lines && lines.count == 2 &&
           lines[0].length == TOKEN_B64 &&
           lines[1].length == NONCE_B64
      fail "process_cmd malformed preamble command body, #{lines ? lines.count : 0} lines"
    end
    lines
  end

  def _check_body_command_lines(body)
    lines = _check_body_break_lines body
    unless lines && lines.count == 1
      fail "wrong number of lines in command body, #{lines ? lines.count : 0} lines"
    end
    lines
  end

  def _check_body_break_lines(body)
    fail 'No request body' if body.nil? || body.empty?
    nl = body.include?("\r\n") ? "\r\n" : "\n"
    body.split nl
  end

  def _decrypt_data(nonce, ctext)
    box = RbNaCl::Box.new(@client_key, @session_key)
    d = JSON.parse box.decrypt(nonce, ctext)
    d = d.reduce({}) { |h, (k, v)| h[k.to_sym] = v; h }
    _check_command d
  end

  def _encrypt_data(nonce, data)
    box = RbNaCl::Box.new(@client_key, @session_key)
    b64enc box.encrypt(nonce, data.to_json)
  end

  def _rand_str(min, size)
    (b64enc rand_bytes min + rand(size)).delete('=')
  end

  def _check_command(data)
    all = %w(count upload download delete)

    fail 'command_controller: missing command' unless data[:cmd]
    fail "command_controller: unknown command #{data[:cmd]}" unless all.include? data[:cmd]

    if data[:cmd] == 'upload'
      fail 'command_controller: no destination HPK in upload' unless data[:to]
      hpk_dec = b64dec data[:to]
      _check_hpk hpk_dec
      fail 'command_controller: no payload in upload' unless data[:payload]
    end

    if data[:cmd] == 'delete'
      fail 'command_controller: no ids to delete' unless data[:payload]
    end

    data
  end

  # all of the messages in the mailbox are read out as an array
  def _process_payload(messages)
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

  def _report_error(e)
    logger
      .warn "#{WARN} Process command aborted:\n#{@body}\n#{EXPT} #{e}"
    head :precondition_failed, x_error_details:
      "Can't process command: #{e.message}"
  end
end
