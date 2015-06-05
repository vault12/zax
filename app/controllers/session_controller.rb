require "response_helper"

class SessionController < ApplicationController
  include ResponseHelper

  # GET /session - start handshake
  def new_session_token
    # never cache
    expires_now

    # Checks for correct request id or throws
    rid = _get_request_id

    # Establish and cache server token for timeout duration
    to = Rails.configuration.x.relay.token_timeout
    token = Rails.cache.fetch(rid, expires_in: to) do
      logger.info "#{INFO} Established token for req #{dumpHex rid[0..7]}"
      RbNaCl::Random.random_bytes 32
    end

    # Sanity check server-side RNG
    if not token or token.length != 32
      raise RequestIDError.new(self,token),
        "Missing #{TOKEN} header"
    end

    # Send back our token as base64 response body
    render text: b64enc(token)

    rescue => e
      return e.http_fail if e.respond_to? :http_fail
      logger.error "#{ERROR} new_session_token error | rid: #{dumpHex rid[0..7]}\n#{EXPT} #{e}"
      head :internal_server_error, x_error_details: "Server-side error: try again later"
  end

  # POST /session - end handshake
  def verify_session_token
    expires_now

    # Let's see if we got correct request_token
    rid = _get_request_id

    # Client have to conclude the handshike while our token is cached
    # Report expiration to log and user
    unless (token = Rails.cache.fetch rid)
      raise ExpiredError.new(self,rid),
        "Server handshake token missing or expired"
    end

    # Verify handshake: user request token XOR our token
    body = request.body.read TOKEN_B64 # exact base64 of 32 bytes
    handshake = b64dec body
    raise "Handshake mismatch" unless handshake.eql? (xor_str token, rid)
    logger.info "#{INFO} Succesful handshake for req #{dumpHex rid[0..7]}"

    # establish session keys
    to = Rails.configuration.x.relay.session_timeout
    session_key = Rails.cache.fetch("key_#{rid}",expires_in: to) do
        logger.info "#{INFO_GOOD} Generated new session key for req #{dumpHex rid[0..7]}"
        # refresh token for same expiration timeout
        Rails.cache.write(rid, token, :expires_in => to)
        RbNaCl::PrivateKey.generate
    end

    # report errors with keys if any
    if session_key.nil? or session_key.public_key.to_bytes.length!=32
      raise KeyError.new(self,session_key),
        "Session key failed or too short"
    end

    # Send session pub_key back to user as base64 body
    expires_in to, :public => false
    render text: "#{b64enc session_key.public_key.to_bytes}"

    # Report handshake errors
    rescue => e
      return e.http_fail if e.respond_to? :http_fail

      logger.warn "#{WARN} handshake problem | rid: #{dumpHex rid[0..7]}\n#{EXPT} #{e}"
      head :conflict, x_error_details: "Provide session handshake (your token XOR our token) as base64 body"
  end
end