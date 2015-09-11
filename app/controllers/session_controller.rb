class SessionController < ApplicationController
  before_filter :_preamble

  # POST /start_session - start handshake
  def start_session_token
    # ready only number of bytes we expect
    body = request.body.read SESSION_START_BODY

    # we expect 1 line to start session
    lines = _check_body_lines body, 1, 'start session'

    # check that client token is valid
    @client_token = _check_client_token lines[0]

    # lets make relay token to initiate handshake
    @relay_token  = _make_relay_token

    # save both tokens to redis
    _cache_tokens

    # Send back our token as base64 response body
    render text: b64enc(@relay_token)

  rescue ZAXError => e
    # handle known protocol errors
    e.http_fail 
  rescue => e
    # That is unexpected, fail the request
    logger.error "#{ERROR} start_session_token error: #{e}"
    head :internal_server_error, x_error_details:
      'Relay error: try again later'
  end

  # POST /verify_session - verify started handshake
  def verify_session_token
    # read only bytes we expect for verification
    body = request.body.read SESSION_VERIFY_BODY

    # original token and signature in 2 lines
    lines = _check_body_lines body, 2, 'verify session'

    # check that client token line is valid
    _check_client_token lines[0]

    # decode and check both lines
    decode = _decode_lines lines

    # check handshake or throw error
    # returns client_token and its h2() from cache
    ct, h2_ct = _verify_handshake(decode)
    
    # signature is valid, lets make temp keys
    session_key = _make_session_key h2_ct

    # resond with relay temp key for this session
    # masked by client token
    render text: "#{b64enc(xor_str(session_key.public_key.to_bytes, ct))}"

  rescue ZAXError => e
    # handle known protocol errors
    e.http_fail
  rescue => e
    # unexpected errors, such as encoding, etc.
    logger.warn "#{WARN} verify_session_token error:\n"\
      "#{EXPT} #{e}"
    head :conflict, x_error_details: 'Provide session handshake: h2(client,relay)'
  end

  # ----- Private helper functions ----
  private
   # runs before every response
   def _preamble
    # never cache
    expires_now 
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

  def _decode_lines(lines)
    lines.map do |l|
      if l.length == TOKEN_B64
        b64dec l
      else
        fail ReportError.new self,
          msg:"verify_session lines wrong size, expecting #{TOKEN_B64}"
      end
    end
  end

  def _load_cached_tokens(h2_ct)
    ct = Rails.cache.read "client_token_#{h2_ct}"
    if ct.nil? || ct.length != TOKEN_LEN
      fail ClientTokenError.new self,
        client_token: ct ? ct[0...8] : nil,
        msg: "session controller: client token not registered/wrong size, expecting #{TOKEN_LEN}b"
    end

    rt = Rails.cache.read "relay_token_#{h2_ct}"
    if rt.nil? || rt.length != TOKEN_LEN
      fail RelayTokenError.new self,
        rt: rt ? rt[0...8] : nil,
        msg: "session controller: relay token not registered/wrong size, expecting #{TOKEN_LEN}b"
    end
    [ct,rt]
  end

  def _verify_handshake(lines)
    h2_client_token, h2_client_sign = lines
    ct, rt = _load_cached_tokens(h2_client_token)
    fail '_verify_handshake mismatch: wrong client token' unless h2_client_token.eql? h2(ct)
    correct_sign = h2(ct + rt)
    fail '_verify_handshake mismatch: wrong handshake signature' unless h2_client_sign.eql? correct_sign
    [ct, h2_client_token]
  end

  def _make_session_key(h2_client_token)
    # establish session keys
    session_key = RbNaCl::PrivateKey.generate
    # report errors with keys if any
    if session_key.nil? || session_key.public_key.to_bytes.length != KEY_LEN
      fail KeyError.new(self, msg: 'New session key: generation failed or too short')
    end
    Rails.cache.write(
      "session_key_#{h2_client_token}",
      session_key,
      expires_in: Rails.configuration.x.relay.session_timeout )
    session_key
  end
end
