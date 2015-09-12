require 'mailbox'

class ProofController < ApplicationController
  PROVE_CIPHER_B64 = 256

  # POST /prove - prove client ownership of secret key for HPK
  def prove_hpk
    # We expect 5 lines, base64 each:
    # 1: h₂(client_token): client_token used to receive relay session pk 
    # 2: h₂(comm_pk) ⊕ h₂(relay_token): Masked hpk to prove
    # 3: a_temp_pk ⊕ h₂(relay_token): Masked client temp session key
    # 4: nonce_outter: timestamped nonce
    # 5: crypto_box(JSON, nonce_inner, relay_session_pk, client_temp_sk): Outer crypto-text

    body = request.body.read PROVE_BODY
    l1,l2,l3,l4,l5 = _check_body_lines body, 5, 'prove hpk'

    # check and decrypt h2(client_token)
    @h2_ct = _check_client_token l1

    # load @client_token, @relay_token, @session_key from redis
    _check_session_state

    # hash of relay token client uses for masking
    h2_rt = h2 @relay_token

    # unmask hpk
    @hpk = _unmask_line(l2, h2_rt)
    
    # unmask client_temp_pk
    @client_temp_pk = _unmask_line(l3, h2_rt)

    # check that nonce timestamp is within range
    nonce_outer = _check_nonce b64dec l4

    # decode outter cyphertext 
    ctext       = b64dec l5

    # decypher it
    outer_box   = RbNaCl::Box.new(@client_temp_pk, @session_key)
    inner = JSON.parse outer_box.decrypt(nonce_outer, ctext)

    # decode values from base64 and make keys symbols
    inner = Hash[inner.map { |k, v| [k.to_sym, b64dec(v)] }]

    # check inner nonce timestamp
    _check_nonce inner[:nonce]

    # that is the key that is supposed to hash into hpk
    client_comm_pk = inner[:pub_key]

    # dechypher inner ctext
    inner_box = RbNaCl::Box.new(client_comm_pk, @session_key)
    sign = inner_box.decrypt(inner[:nonce], inner[:ctext])

    # construct hash that depends on session 
    # token pair and on the temp key client sent
    proof_sign = h2(@client_temp_pk + @relay_token + @client_token)
    fail 'Signature mismatch' unless sign &&
      proof_sign && sign.eql?(proof_sign) &&
      proof_sign.length == TOKEN_LEN
    fail 'HPK mismatch' unless @hpk.eql? h2(inner[:pub_key])

    # --- No exceptions so far - now its proof success path ---
    _save_hpk_session
    _delete_handshake_keys
    mailbox = Mailbox.new @hpk
    render text: "#{mailbox.count}", status: :ok

  rescue RbNaCl::CryptoError => e
    _report_NaCl_error e
  rescue ZAXError => e
    e.http_fail
  rescue => e
    _report_error e
  end

  # ----- Private helper functions ----
  private
  def _check_session_state
    @client_token = Rails.cache.read("client_token_#{@h2_ct}")
    @relay_token = Rails.cache.read("relay_token_#{@h2_ct}")
    @session_key = Rails.cache.read("session_key_#{@h2_ct}")

    # raise error if bad session state
    if @session_key.nil? || @session_key.to_bytes.length != KEY_LEN ||
       @relay_token.nil? || @relay_token.length != TOKEN_LEN ||
       @client_token.nil? || @client_token.length != TOKEN_LEN
      fail SessionKeyError.new self,
        session_key: @session_key.to_bytes[0..3],
        relay_token: @relay_token[0..3],
        client_token: @client_token[0..3]
    end
  end

  def _check_body(body)
    lines = super body
    unless lines && lines.count == 5 &&
           lines[0].length == TOKEN_B64 &&
           lines[1].length == KEY_B64 &&
           lines[2].length == KEY_B64 &&
           lines[3].length == NONCE_B64 &&
           lines[4].length == PROVE_CIPHER_B64
      fail "prove_hpk malformed body, #{lines ? lines.count : 0} lines"
    end
    lines
  end

  def _check_client_key(key_line)
    xor_key = b64dec key_line
    key = xor_str xor_key, h2(@token)
    fail "Bad client key: #{dump key}" unless
      key && key.bytes.length == KEY_LEN
    key
  end

  def _unmask_line(line, mask)
    xor_str b64dec(line), mask
  end

  def _save_hpk_session
    # Increase timeouts and save session data on HPK key
    tmout = Rails.configuration.x.relay.session_timeout
    Rails.cache.write("session_key_#{@hpk}", @session_key, expires_in: tmout)
    Rails.cache.write("client_key_#{@hpk}", @client_temp_pk, expires_in: tmout)
    logger.info "#{INFO_GOOD} Saved client and session key for hpk #{b64enc @hpk}"
  end

  def _delete_handshake_keys
    Rails.cache.delete("client_token_#{@h2_ct}")
    Rails.cache.delete("relay_token_#{@h2_ct}")
    Rails.cache.delete("session_key_#{@h2_ct}")
  end

  def _report_error(e)
    logger.warn "#{WARN} Aborted prove_hpk key exchange:\n"\
      "#{EXPT} #{e}"
    head :precondition_failed, x_error_details:
      'prove hpk ownership: provide 5 lines block in base64 format'
  end
end
