require 'response_helper'

class SessionController < ApplicationController
  # POST /start_session - start handshake
  def start_session_token
    expires_now # never cache
    @tmout = Rails.configuration.x.relay.token_timeout

    @body = request.body.read SESSION_START_BODY
    lines = _check_body_lines @body, 1, 'start session'
    unless lines[0].length == TOKEN_B64
      fail "start_session_token malformed body, #{lines ? lines.count : 0} lines"
    end
    client_token = b64dec lines[0]
    _check_client_token client_token
    _cache_client_token client_token
    relay_token = _make_relay_token client_token
    # Send back our token as base64 response body
    render text: b64enc(relay_token)
  rescue ZAXError => e
    e.http_fail
  rescue => e
    logger.error "#{ERROR} start_session_token error for client_token: #{e}"
    head :internal_server_error, x_error_details:
      'Server-side error: try again later'
  end

  # POST /verify_session - verify started handshake
  def verify_session_token
    expires_now
    @tmout = Rails.configuration.x.relay.session_timeout
    @body = request.body.read SESSION_VERIFY_BODY

    lines = _check_body_lines @body, 2, 'verify session'
    unless lines[0].length == TOKEN_B64 &&
           lines[1].length == TOKEN_B64
      fail "verify_session_token malformed body, #{lines ? lines.count : 0} lines"
    end

    # check handshake or throw error
    client_token, h2_client_token = _verify_handshake(lines)
    session_key = _make_session_key h2_client_token

    session_key_xor_client_token = xor_str(session_key.public_key.to_bytes, client_token)
    session_key_xor_client_token = b64enc session_key_xor_client_token
    render text: "#{session_key_xor_client_token}"

  rescue ZAXError => e
    e.http_fail
  rescue => e
    _report_error e
  end

  private

  def _verify_handshake(lines)
    chk_h2_client_token = b64dec lines[0]
    chk_h2_client_relay = b64dec lines[1]

    client_token = Rails.cache.read "client_token_#{chk_h2_client_token}"
    if client_token.nil? || client_token.length != KEY_LEN
      e = ClientTokenError.new self,
                               client_token: client_token[0..3],
                               msg: 'session controller: client token not in cache or equal to 32'
      fail e
    end

    h2_client_token = h2(client_token)
    fail '_verify_handshake mismatch h2_client_token' unless chk_h2_client_token.eql? h2_client_token

    relay_token = Rails.cache.read "relay_token_#{h2_client_token}"
    if relay_token.nil? || relay_token.length != KEY_LEN
      e = RelayTokenError.new self,
                              relay_token: relay_token[0..3],
                              msg: 'session controller: relay token not in cache or equal to 32'
      fail e
    end

    client_relay = client_token + relay_token
    h2_client_relay = h2(client_relay)

    fail '_verify_handshake mismatch h2_client_relay in versus calculate' unless chk_h2_client_relay.eql? h2_client_relay
    [client_token, h2_client_token]
  end

  def _make_relay_token(client_token)
    relay_token = RbNaCl::Random.random_bytes(32)
    h2_client_token = h2(client_token)
    Rails.cache.write("relay_token_#{h2_client_token}", relay_token, expires_in: @tmout)
    # Sanity check server-side RNG
    if !relay_token || relay_token.length != 32
      fail RequestIDError.new(self, relay_token), "Missing #{TOKEN}"
    end
    relay_token
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

  def _check_client_token(client_token)
    unless client_token.length == TOKEN_LEN
      e = ClientTokenError.new self,
                               client_token: client_token[0..3],
                               msg: 'session controller, _check_client_token is not 32 bytes'
      fail e
    end
  end

  def _cache_client_token(client_token)
    h2_client_token = h2(client_token)
    Rails.cache.write("client_token_#{h2_client_token}", client_token, expires_in: @tmout)
  end

  def _report_error(e)
    logger.warn "#{WARN} verify_session_token error:\n"\
      "#{EXPT} #{e}"
    head :conflict, x_error_details:
      'Provide session handshake: your token AND our token as base64 body'
  end
end
