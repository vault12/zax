require "response_helper"

class SessionController < ApplicationController
  include ResponseHelper

  # GET /session - start handshake
  def new_session_token
    expires_now # never cache
    @tmout = Rails.configuration.x.relay.token_timeout
    # Checks for correct request id or throws
    @rid = _get_request_id
    _make_random_token
    # Send back our token as base64 response body
    render text: b64enc(@token)
    rescue ZAXError => e
      e.http_fail
    rescue => e
      logger.error "#{ERROR} new_session_token error rid:"\
        "#{dumpHex @rid[0..7]}\n#{EXPT} #{e}"
      head :internal_server_error, x_error_details:
        "Server-side error: try again later"
  end

  # POST /session - verify started handshake
  def verify_session_token
    expires_now 
    @tmout = Rails.configuration.x.relay.session_timeout

    # got correct request_token?
    @rid = _get_request_id
    # server random token pre-established?
    _get_cached_token
    # check handshake or throw error
    _verify_handshake
    @session_key = _make_session_keys
  
    # Send session pub_key back to user as base64 body
    expires_in @tmout, :public => false
    render text: "#{b64enc @session_key.public_key.to_bytes}"

    # Report handshake errors
    rescue ZAXError => e
      e.http_fail
    rescue => e
      _report_error e
  end

  # --- Helper functions ---
  private

  def _make_random_token
    # Establish and cache server token for timeout duration
    @token = Rails.cache.fetch(@rid, expires_in: @tmout) do
      logger.info "#{INFO} Established token for req #{dumpHex @rid[0..7]}"
      rand_bytes 32
    end
    # Sanity check server-side RNG
    if not @token or @token.length != 32
      raise RequestIDError.new(self,@token), "Missing #{TOKEN} header"
    end
    return @token
  end

  # Client have to conclude the handshike while our token is cached
  # Report expiration to log and user
  def _get_cached_token
    unless (@token = Rails.cache.fetch @rid)
      raise ExpiredError.new(self,@rid),
        "Server handshake token missing or expired"
    end
    return @token
  end

  # Verify handshake: user request token XOR our token
  def _verify_handshake
    @body = request.body.read TOKEN_B64 # exact base64 of 32 bytes
    @handshake = b64dec @body
    raise "Handshake mismatch" unless @handshake.eql? (xor_str @token, @rid)
    logger.info "#{INFO} Succesful handshake for req #{dumpHex @rid[0..7]}"
    return @body
  end

  def _make_session_keys
    # establish session keys
    session_key = Rails.cache.fetch("key_#{@rid}",expires_in: @tmout) do
      logger.info "#{INFO_GOOD} Generated new session key for req #{dumpHex @rid[0..7]}"
      # refresh token for same expiration timeout
      Rails.cache.write(@rid, @token, :expires_in => @tmout)
      RbNaCl::PrivateKey.generate
    end
    # report errors with keys if any
    if session_key.nil? or session_key.public_key.to_bytes.length!=32
      raise KeyError.new(self,session_key),
        "Session key failed or too short"
    end
    return session_key
  end

  # --- Error reporting ---

  def _report_error(e)
    logger.warn "#{WARN} handshake problem:\n"\
      "body: #{@body} rid #{dumpHex @rid[0..7]}\n"\
      "#{EXPT} #{e}"
    head :conflict, x_error_details:
      "Provide session handshake: your token XOR our token as base64 body"
  end
end