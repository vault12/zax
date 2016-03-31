# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class ProofController < ApplicationController
  PROVE_CIPHER_B64 = 256
  attr_reader :body

  # POST /prove - prove client ownership of a secret key for HPK
  def prove_hpk
    # We expect 4 lines, base64 each:
    # 1: h₂(client_token): client_token used to receive a relay session pk
    # 2: a_temp_pk : client temp session key
    # 3: nonce_outter: timestamped nonce
    # 4: crypto_box(JSON, nonce_inner, relay_session_pk, client_temp_sk): Outer crypto-text

    @body = request.body.read PROVE_BODY
    l1, l2, l3, l4 = _check_body_lines @body, 4, 'prove hpk'

    # check and decrypt h2(client_token)
    @h2_ct = _check_client_token l1

    # load @client_token, @relay_token, @session_key from redis
    check_session_state

    # client_temp_pk
    @client_temp_pk = b64dec l2

    # check that nonce timestamp is within range
    nonce_outer = _check_nonce b64dec l3

    # decode outter cyphertext
    ctext = b64dec l4

    # decypher it
    outer_box = RbNaCl::Box.new(@client_temp_pk, @session_key)
    inner = JSON.parse outer_box.decrypt(nonce_outer, ctext)

    # decode values from base64 and make keys symbols
    inner = Hash[inner.map { |k, v| [k.to_sym, b64dec(v)] }]

    # check inner nonce timestamp
    _check_nonce inner[:nonce]

    # inner[:pub_key] is the key that is supposed to hash into hpk
    # dechypher inner ctext
    inner_box = RbNaCl::Box.new(inner[:pub_key], @session_key)
    sign = inner_box.decrypt(inner[:nonce], inner[:ctext])

    # construct the hash that depends on the session
    # token pair and on the temp key client sent
    proof_sign = h2(@client_temp_pk + @relay_token + @client_token)

    fail HPKError.new(self, msg:'HPK prove: Signature mismatch') unless sign &&
      proof_sign && proof_sign.length == TOKEN_LEN && sign.eql?(proof_sign)

    # Set HPK to the hash of idenitity key we just decrypted with
    @hpk = h2(inner[:pub_key])

    # --- No exceptions so far - now it is the proof success path ---
    save_hpk_session
    delete_handshake_keys
    mailbox = Mailbox.new @hpk
    render text: "#{mailbox.count}", status: :ok

  rescue RbNaCl::CryptoError => e
    ZAXError.new(self).NaCl_error e
  rescue ZAXError => e
    e.http_fail
  rescue => e
    ZAXError.new(self).report 'prove_hpk error', e
  end

  # === Private helper functions ===
  private

  # For the ownership verification process we need a pre-established
  # client_token, relay_token and session_key
  def check_session_state
    @client_token = Rails.cache.read("client_token_#{@h2_ct}")
    @relay_token = Rails.cache.read("relay_token_#{@h2_ct}")
    @session_key = Rails.cache.read("session_key_#{@h2_ct}")

    # raise an error if in a bad session state
    if @session_key.nil? || @session_key.to_bytes.length != KEY_LEN ||
       @relay_token.nil? || @relay_token.length != TOKEN_LEN ||
       @client_token.nil? || @client_token.length != TOKEN_LEN
      fail SessionKeyError.new self,
        session_key: @session_key.to_bytes[0..3],
        relay_token: @relay_token[0..3],
        client_token: @client_token[0..3]
    end
  end

  # Verify the exact body structure we expect for this call
  def _check_body(body)
    lines = super body
    unless lines && lines.count == 4 &&
           lines[0].length == TOKEN_B64 &&
           lines[1].length == KEY_B64 &&
           lines[2].length == NONCE_B64 &&
           lines[3].length == PROVE_CIPHER_B64
      fail BodyError.new self, msg: "_prove_hpk: malformed body - #{lines ? lines.count : 0} lines"
    end
    lines
  end

  # decocde the client line from base64, then de-mask by applying a specific pad
  def unmask_line(line, mask)
    xor_str b64dec(line), mask
  end

  # Once hpk ownership is proven, increase client/relay key storage
  # timeouts to match the full session duration.
  def save_hpk_session
    # Increase timeouts and save session data on HPK key
    tmout = Rails.configuration.x.relay.session_timeout
    Rails.cache.write("session_key_#{@hpk}", @session_key, expires_in: tmout)
    Rails.cache.write("client_key_#{@hpk}", @client_temp_pk, expires_in: tmout)
    logger.info "#{INFO_GOOD} Saved client and session key for hpk #{dumpHex @hpk}"
  end

  # Delete handshake tokens. We delete the session key as well since it is now
  # stored on the hpk tag.
  def delete_handshake_keys
    Rails.cache.delete("client_token_#{@h2_ct}")
    Rails.cache.delete("relay_token_#{@h2_ct}")
    Rails.cache.delete("session_key_#{@h2_ct}")
  end
end
