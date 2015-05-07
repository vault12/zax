require "base64"
require "log_codes"

class SessionController < ApplicationController
  private
  include LogCodes
  TOKEN   = "REQUEST_TOKEN"

  def _get_request_id
    begin
      rth = request.headers["HTTP_#{TOKEN}"]
      raise "Missing #{TOKEN} header" unless rth
      rid = Base64.strict_decode64 rth
      raise "#{TOKEN} is not 32 bytes" unless rid.length == 32
      return rid
    rescue => e
      logger.warn "#{WARN} HTTP_#{TOKEN} (base64): "\
      "#{ rth ? rth.dump : ''} => #{e}"
      head :precondition_failed,
        error_details: "Provide #{TOKEN} header: 32 bytes (base64)"
    end
    return nil
  end

  # Responds with 412, 500 or 200 OK
  public
  def new_session_token
    return unless rid = _get_request_id  # Enforce token header or fail 412
    token = Rails.cache.fetch(rid,
      expires_in: Rails.configuration.x.relay.new_session_token_timeout) do
        logger.info "#{INFO} Established token for req #{rid.bytes[0..4]}..."
        RbNaCl::Random.random_bytes 32
    end
    if not token or token.length != 32
      logger.error "#{ERROR} NaCl random(32) error:"\
      " len=#{token ? token.length : 'nil'}"
      head :internal_server_error,
        error_details: "Local entropy fail; try again?"
      return
    end
    render text: Base64.strict_encode64(token)
  end

  # Responds with 412, 409 or 200 OK
  def verify_session_token
    # enforce token header or fail 412
    return unless rid = _get_request_id 
    unless (token = Rails.cache.fetch rid)
      logger.info "#{INFO_NEG} request for expired req #{rid.bytes[0..4]}"
      to = Rails.configuration.x.relay.new_session_token_timeout
      head :precondition_failed,
           error_details: "Your #{TOKEN} expired after #{to} seconds"
      return
    end

    # verify handshake
    begin
      body = request.body.read 44 # exact base64 of 32 bytes
      handshake = Base64.strict_decode64 body
      xored = token.bytes.zip(rid.bytes).map { |a,b| a^b }.pack("C*")
      raise "Handshake mismatch" unless handshake.eql? xored
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

    render text: "#{Base64.strict_encode64 session_key.public_key.to_bytes}"
  end
end