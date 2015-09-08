require 'response_helper'

class SessionController < ApplicationController
  before_filter :_preamble

  # POST /start_session - start handshake
  def start_session_token
    @body = request.body.read SESSION_START_BODY
    lines = _check_body_lines @body, 1, 'start session'
    @client_token = _check_client_token lines[0]
    @relay_token  = _make_relay_token
    _cache_tokens

    # Send back our token as base64 response body
    render text: b64enc(@relay_token)

  rescue ZAXError => e
    e.http_fail
  rescue => e
    logger.error "#{ERROR} start_session_token error: #{e}"
    head :internal_server_error, x_error_details:
      'Server-side error: try again later'
  end

  # POST /verify_session - verify started handshake
  def verify_session_token
    @tmout = Rails.configuration.x.relay.session_timeout
    @body = request.body.read SESSION_VERIFY_BODY

    lines = _check_body_lines @body, 2, 'verify session'
    lines.each { |l| fail ReportError.new self,
      msg:"verify_session lines wrong size, expecting #{TOKEN_B64}" if l.length != TOKEN_B64
    }

    # check handshake or throw error
    client_token, h2_client_token = _verify_handshake(lines)
    session_key = _make_session_key h2_client_token

    session_key_xor_client_token = xor_str(session_key.public_key.to_bytes, client_token)
    session_key_xor_client_token = b64enc session_key_xor_client_token
    render text: "#{session_key_xor_client_token}"

  rescue ZAXError => e
    e.http_fail
  rescue => e
    logger.warn "#{WARN} verify_session_token error:\n"\
      "#{EXPT} #{e}"
    head :conflict, x_error_details: 'Provide session handshake: h2(client,relay)'
  end

  # ----- Private helper functions ----
  private
   def _preamble
    expires_now # never cache
   end

   def _make_relay_token
    relay_token = RbNaCl::Random.random_bytes(TOKEN_LEN)
    # Sanity check server-side RNG
    if !relay_token || relay_token.length != TOKEN_LEN
      fail RandomError.new
    end
    relay_token
  end

  def _cache_tokens
    h2_client_token = h2 @client_token
    Rails.cache.write "client_token_#{h2_client_token}",
      @client_token,
      expires_in: Rails.configuration.x.relay.token_timeout

    Rails.cache.write "relay_token_#{h2_client_token}",
      @relay_token,
      expires_in: Rails.configuration.x.relay.token_timeout
  end

  def _verify_handshake(lines)
    chk_h2_client_token = b64dec lines[0]
    chk_h2_client_relay = b64dec lines[1]

    # client_token
    ct = Rails.cache.read "client_token_#{chk_h2_client_token}"
    if ct.nil? || ct.length != TOKEN_LEN
      fail ClientTokenError.new self,
        client_token: ct ? ct[0...8] : nil,
        msg: "session controller: client token not registered/wrong size, expecting #{TOKEN_LEN}b"
    end

    h2_client_token = h2 ct
    fail '_verify_handshake mismatch h2_client_token' unless chk_h2_client_token.eql? h2_client_token

    relay_token = Rails.cache.read "relay_token_#{h2_client_token}"
    if relay_token.nil? || relay_token.length != TOKEN_LEN
      e = RelayTokenError.new self,
            relay_token: relay_token[0..3],
            msg: 'session controller: relay token not in cache or equal to 32'
      fail e
    end

    client_relay = ct + relay_token
    h2_client_relay = h2(client_relay)

    fail '_verify_handshake mismatch h2_client_relay in versus calculate' unless chk_h2_client_relay.eql? h2_client_relay
    [ct, h2_client_token]
  end

  def _make_session_key(h2_client_token)
    # establish session keys
    session_key = RbNaCl::PrivateKey.generate
    # report errors with keys if any
    if session_key.nil? || session_key.public_key.to_bytes.length != 32
      fail KeyError.new(self, session_key),
           'Session key failed or too short'
    end
    Rails.cache.write("session_key_#{h2_client_token}", session_key, expires_in: @tmout)
    session_key
  end
end
