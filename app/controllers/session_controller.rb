require "base64"
require "log_codes"

class SessionController < ApplicationController
  private
  include LogCodes
  TOKEN   = "REQUEST_TOKEN"

  def _get_request_id
    # Let's make sure everything is correct with request_token
    begin
      rth = request.headers["HTTP_#{TOKEN}"]
      raise "Missing #{TOKEN} header" unless rth
      rid = Base64.strict_decode64 rth
      raise "#{TOKEN} is not 32 bytes" unless rid.length == 32
      return rid

    # Can not get request token: report to log and to client
    rescue => e
      logger.warn "#{WARN} HTTP_#{TOKEN} (base64): "\
      "#{ rth ? rth.dump : ''} => #{e}"
      expires_now
      head :precondition_failed,
        error_details: "Provide #{TOKEN} header: 32 bytes (base64)"
    end
    return nil
  end

  # GET /session - start handshake
  # Responds with 412, 500 or 200 OK
  public
  def new_session_token

    # Let's see if we got correct request_token
    return unless rid = _get_request_id  # Enforce token header or fail 412
    to = Rails.configuration.x.relay.new_session_token_timeout

    # Establish and cache our token for timeout duration
    token = Rails.cache.fetch(rid, expires_in: to) do
        logger.info "#{INFO} Established token for req #{rid.bytes[0..4]}..."
        expires_in to, :public => false
        RbNaCl::Random.random_bytes 32
    end

    # Make sure our RNG is working
    if not token or token.length != 32
      logger.error "#{ERROR} NaCl error - random(32):"\
      " len=#{token ? token.length : 'nil'}"
      head :internal_server_error,
        error_details: "Local entropy fail; try again?"
      expires_now
      return
    end

    # Send back our token as base64 response body
    render text: Base64.strict_encode64(token)
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
      logger.info "#{INFO_NEG} request for expired req #{rid.bytes[0..4]}"
      to = Rails.configuration.x.relay.new_session_token_timeout
      head :precondition_failed,
           error_details: "Your #{TOKEN} expired after #{to} seconds"
      return
    end

    # Verify handshake: user request token XOR our token
    begin
      body = request.body.read 44 # exact base64 of 32 bytes
      handshake = Base64.strict_decode64 body
      xored = token.bytes.zip(rid.bytes).map { |a,b| a^b }.pack("C*")
      raise "Handshake mismatch" unless handshake.eql? xored

    # Report handshake errors
    rescue => e
      logger.warn "#{WARN} handshake '#{body}' => #{e}"
      head :conflict,
        error_details: "Provide session handshake "\
        "(your token XOR our token) as base64 body"
      return
    end

    logger.info "#{INFO} Succesful handshake for req #{rid.bytes[0..4]}"
    # establish session keys
    session_key = Rails.cache.fetch("#key_{rid}",
      expires_in: Rails.configuration.x.relay.session_timeout) do
        logger.info "#{INFO_GOOD} Generated new key for req #{rid.bytes[0..4]}..."
        RbNaCl::PrivateKey.generate
    end

    # report errors with keys if any
    if session_key.nil? or session_key.public_key.to_bytes.length!=32
      logger.error "#{ERROR} NaCl error - generate keys: "\
      "#{session_key ? session_key.to_s.dump : 'nil'}"
      head :internal_server_error,
        error_details: "Can't generate new keys; try again?"
      return
    end

    # Send session pub_key back to user as base64 body
    render text: "#{Base64.strict_encode64 session_key.public_key.to_bytes}"
  end
end