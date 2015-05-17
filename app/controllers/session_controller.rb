require "response_helper"

class SessionController < ApplicationController
  private
  include ResponseHelper

  public
  # GET /session - start handshake
  # Responds with 412, 500 or 200 OK
  def new_session_token
    # never cache
    expires_in 0, :public => false

    # Let's see if we got correct request_token
    # Enforce token header or fail 412
    return unless rid = _get_request_id

    to = Rails.configuration.x.relay.token_timeout

    # Establish and cache our token for timeout duration
    token = Rails.cache.fetch(rid, expires_in: to) do
        logger.info "#{INFO} Established token for req #{rid.bytes[0..3]}"
        RbNaCl::Random.random_bytes 32
    end

    # Make sure server-side RNG is working
    if not token or token.length != 32
      logger.error "#{ERROR} NaCl error - random(32): #{dump token}"
      head :internal_server_error,
        x_error_details: "Local entropy fail; try again?"
      return
    end

    # Send back our token as base64 response body
    render text: b64enc(token)
  end

  # POST /session - end handshake
  # Responds with 412, 409 or 200 OK
  def verify_session_token
    expires_now # never cache this response until it succeeds

    # Let's see if we got correct request_token
    return unless rid = _get_request_id

    # Client have to conclude the handshike while our token is cached
    # Report expiration to log and user
    unless (token = Rails.cache.fetch rid)
      logger.info "#{INFO_NEG} 'verify' for expired req #{rid.bytes[0..3]}"
      to = Rails.configuration.x.relay.token_timeout
      head :precondition_failed,
           x_error_details: "Your #{TOKEN} expired after #{to} seconds"
      return
    end

    # Verify handshake: user request token XOR our token
    begin
      body = request.body.read 44 # exact base64 of 32 bytes
      handshake = b64dec body
      raise "Handshake mismatch" unless handshake.eql? (xor_str token, rid)

    # Report handshake errors
    rescue => e
      logger.warn "#{WARN} handshake:\n#{body}\n#{EXPT}#{e}"
      head :conflict,
        x_error_details: "Provide session handshake "\
        "(your token XOR our token) as base64 body"
      return
    end

    logger.info "#{INFO} Succesful handshake for req #{rid.bytes[0..3]}"
    # establish session keys
    to = Rails.configuration.x.relay.session_timeout
    session_key = Rails.cache.fetch("key_#{rid}",expires_in: to) do
        logger.info "#{INFO_GOOD} Generated new session key "\
                    "for req #{rid.bytes[0..3]}..."
        # refresh token for same expiration timeout
        Rails.cache.write(rid, token, :expires_in => to)
        RbNaCl::PrivateKey.generate
    end

    # report errors with keys if any
    if session_key.nil? or session_key.public_key.to_bytes.length!=32
      logger.error "#{ERROR} NaCl error - generate keys\n#{EXPT} #{dump session_key}"
      head :internal_server_error,
        x_error_details: "Can't generate new keys; try again?"
      return
    end

    # Send session pub_key back to user as base64 body
    render text: "#{b64enc session_key.public_key.to_bytes}"
  end
end