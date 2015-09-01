require 'mailbox'

class ProofController < ApplicationController
  PROVE_CIPHER_B64 = 256

  # POST /prove - prove client ownership of dual key for HPK
  def prove_hpk
    # Get basic request data
    # _good_session_state? # Load memcached session state or fail

    # --- process request body ---
    # POST lines:
    #  masked client session key 32b = 44b base64
    #  nonce 24b = 32b base64
    #  ciphertext 192b = 256b base64

    # TODO Figure out what this number should be...
    # @body = request.body.read KEY_B64+2+NONCE_B64+2+PROVE_CIPHER_B64

    @body = request.body.read PROVE_BODY
    lines = _check_body_lines @body, 5, 'prove hpk'

    @h2_client_token = b64dec lines[0]
    _good_session_state?

    #print "pc @relay_token = #{b64enc @relay_token}"; puts
    #print "pc masked_hpk = #{lines[1]}"; puts
    #print "pc masked_client_temp_pk = #{lines[2]}"; puts

    h2_relay_token = h2(@relay_token)

    masked_hpk = b64dec lines[1]
    @hpk = xor_str(masked_hpk,h2_relay_token)
    masked_client_temp_pk = b64dec lines[2]
    @client_temp_pk = xor_str(masked_client_temp_pk,h2_relay_token)

    #print "pc @hpk = #{b64enc @hpk}"; puts
    #print "pc @client_temp_pk = #{b64enc @client_temp_pk}"; puts

    nonce_outer = _check_nonce b64dec lines[3]
    ctext = b64dec lines[4]

    outer_box = RbNaCl::Box.new(@client_temp_pk,@session_key)
    inner = JSON.parse outer_box.decrypt(nonce_outer,ctext)
    inner = Hash[ inner.map { |k,v| [k.to_sym,b64dec(v)] } ]

    _check_nonce inner[:nonce]
    client_comm_pk = inner[:pub_key]
    inner_box = RbNaCl::Box.new(client_comm_pk,@session_key)
    sign  = inner_box.decrypt(inner[:nonce],inner[:ctext])
    proof_sign1 = concat_str(@client_temp_pk,@relay_token)
    proof_sign = concat_str(proof_sign1,@client_token)
    proof_sign = h2 proof_sign
    raise "Signature mismatch" unless sign and proof_sign and
                                      sign.eql? proof_sign and
                                      proof_sign.length == 32
    raise "HPK mismatch" unless @hpk.eql? h2(inner[:pub_key])
    # --- No exceptions: success path now ---
    _save_hpk_session
    mailbox = Mailbox.new @hpk
    render text:"#{mailbox.count}", status: :ok

    rescue RbNaCl::CryptoError => e
      _report_NaCl_error e
    rescue ZAXError => e
      e.http_fail
    rescue => e
      _report_error e
  end

  # === Helper functions ===
  private

  def _good_session_state?
    @client_token = Rails.cache.read("client_token_#{@h2_client_token}")
    @relay_token = Rails.cache.read("relay_token_#{@h2_client_token}")
    @session_key = Rails.cache.read("session_key_#{@h2_client_token}")

    # raise error if bad session state
    if @session_key.nil? or @session_key.to_bytes.length!=KEY_LEN or
       @relay_token.nil? or @relay_token.length!=KEY_LEN or
       @client_token.nil? or @client_token.length!=KEY_LEN
       e = SessionKeyError.new self, session_key: @session_key, relay_token: @relay_token, client_token: @client_token
       raise e, "Bad session state"
    end
  end

  def _existing_client_key?
    # If we already have session key, we keep it
    # for timeout duration, no overwrites
    if Rails.cache.read("client_key_#{@hpk}")
      mailbox = Mailbox.new @hpk
      render text:"#{mailbox.count}", status: :accepted
      return true
    end
    return false
  end

  def _check_body(body)
    lines = super body
    unless lines and lines.count==5 and
      #print 'line 0 = ', lines[0].length
      #print ' line 1 = ', lines[1].length
      #print ' line 2 = ', lines[2].length
      #print ' line 3 = ', lines[3].length
      #print ' line 4 = ', lines[4].length; puts
      lines[0].length==TOKEN_B64 and
      lines[1].length==KEY_B64 and
      lines[2].length==KEY_B64 and
      lines[3].length==NONCE_B64 and
      lines[4].length==PROVE_CIPHER_B64
      raise "prove_hpk malformed body, #{ lines ? lines.count : 0} lines"
    end
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
    tmout = Rails.configuration.x.relay.session_timeout
    Rails.cache.write("session_key_#{@hpk}", @session_key, expires_in: tmout)
    Rails.cache.write("client_key_#{@hpk}", @client_temp_pk, expires_in: tmout)
    logger.info "#{INFO_GOOD} Saved client and session key for hpk #{b64enc @hpk}"
  end

  # === Error reporting ===
  def _report_error(e)
    logger.warn "#{WARN} Aborted prove_hpk key exchange:\n#{@body}\n#{EXPT} #{e}"
    head :precondition_failed, x_error_details:
      "Provide masked pub_key, timestamped nonce and signature as 3 lines in base64"
  end
end
