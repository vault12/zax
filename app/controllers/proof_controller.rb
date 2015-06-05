require "response_helper"

class ProofController < ApplicationController
  include ResponseHelper
  CIPHER_B64 = 256

  # POST /prove - prove client ownership of dual key for HPK
  def prove_hpk
    # Get basic request data
    @rid = _get_request_id
    @hpk = _get_hpk

    return if _existing_client_key?

    # Get cached session state
    @timeout = Rails.configuration.x.relay.session_timeout
    _good_session_state?

    # POST lines:
    #  masked client session key 32b = 44b base64
    #  nonce 24b = 32b base64
    #  ciphertext 192b = 256b base64

    # --- process request body
    @body = request.body.read KEY_B64+2+NONCE_B64+2+CIPHER_B64
    lines = _check_body @body
    
    # --- first line is masked client session key
    @client_key = _check_client_key lines[0]

    # --- second line is outter nonce
    nonce = _check_nonce lines[1]

    # --- third line is outter ciphertext
    outer_box = RbNaCl::Box.new(@client_key,@session_key)
    inner = JSON.parse outer_box.decrypt(nonce,b64dec(lines[2]))
    # decode all values from b64
    inner = Hash[ inner.map { |k,v| [k.to_sym,b64dec(v)] } ]

    # inner box with node permanent comm_key (identity)
    inner_box = RbNaCl::Box.new(inner[:pub_key],@session_key)

    # prove decryption with client comm_key
    sign  = inner_box.decrypt(inner[:nonce],inner[:ctext])
    sign2 = xor_str h2(@rid), h2(@token)
    raise "Signature mis-match" unless sign and sign2 and sign == sign2
    raise "HPK mismatch" unless @hpk == h2(inner[:pub_key])

    # No exceptions: success path now
    _save_hpk_session

    # TODO: render # of messages in mailbox instead
    render text:"200 OK", status: :ok

    rescue RbNaCl::CryptoError => e
      _report_NaCl_error e
    rescue ZAXError => e
      e.http_fail
    rescue => e
      _prove_hpk_default_error e
  end

  # --- Helper functions ---
  private 

  def _existing_client_key?
    # If we already have session key, we keep it
    # for timeout duration, no overwrites
    if Rails.cache.read("client_key_#{@hpk}") then
      #TODO: return # of messages
      render text:"202 OK", status: :accepted
      return true
    end
    return false
  end

  def _good_session_state?
    @token = Rails.cache.fetch(@rid)
    @session_key = Rails.cache.fetch("key_#{@rid}")

    # raise error if bad session state
    if @session_key.nil? or @session_key.to_bytes.length!=KEY_LEN or
       @token.nil? or @token.length!=KEY_LEN
      e = SessionKeyError.new self, session_key: @session_key, token: @token, rid: @rid[0..7]
      raise e, "Bad session state"
    end
  end

  def _check_body(body)
    raise "No request body" if body.nil? or body.empty?
    nl = body.include?("\r\n") ? "\r\n" : "\n"
    lines = body.split nl
    raise "Malformated body" unless lines.count==3 and
      lines[0].length==KEY_B64 and
      lines[1].length==NONCE_B64 and
      lines[2].length==CIPHER_B64
    return lines
  end

  def _check_client_key(key_line)
    xor_key = b64dec key_line
    key = xor_str xor_key, h2(@token)
    raise "Bad client key: #{dump key}" unless 
      key and key.bytes.length==KEY_LEN
    return key
  end

  def _save_hpk_session
    # Increase timeouts and save session data on HPK key
    Rails.cache.write(@rid, @token, expires_in: @timeout)
    Rails.cache.write("key_#{@hpk}", @session_key, expires_in: @timeout)
    Rails.cache.write("client_key_#{@hpk}", @client_key, expires_in: @timeout)
    logger.info "#{INFO_GOOD} Saved client session key for hpk #{b64enc @hpk}"
  end

  # --- Error reporting ---

  def _report_NaCl_error(e)
    e1 = e.is_a?(RbNaCl::BadAuthenticatorError) ? 'The authenticator was forged or otherwise corrupt' : ''
    e2 = e.is_a?(RbNaCl::BadSignatureError) ? 'The signature was forged or otherwise corrupt' : ''
    logger.error "#{ERROR} Decryption error for packet:\n"\
      "#{e1}#{e2}\n"\
      "#{@body}\n#{EXPT} #{e}"
    head :bad_request, x_error_details: "Decryption error"
  end

  def _prove_hpk_default_error(e)
    logger.warn "#{WARN} Aborted prove_hpk key exchange:\n#{@body}\n#{EXPT} #{e}"
    head :precondition_failed, x_error_details:
      "Provide masked pub_key, timestamped nonce and signature as 3 lines in base64"
  end
end