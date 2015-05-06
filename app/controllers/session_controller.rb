require "base64"

class SessionController < ApplicationController
  private
  TOKEN = "REQUEST_TOKEN"

  def _get_request_id
    begin
      rth = request.headers["HTTP_#{TOKEN}"]
      raise "Missing #{TOKEN} header" unless rth
      rid = Base64.strict_decode64 rth
      raise "#{TOKEN} is not 32 bytes" unless rid.length == 32
      return rid
    rescue => e
      logger.warn "(-) base64 HTTP_#{TOKEN}: "\
      "#{ rth ? rth.dump : ''} => #{e}"
      head :precondition_failed,
        error_details: "Provide #{TOKEN} header: 32 bytes, base64 encoded."
    end
    return nil
  end

  # Responds with 412, 500 or 200 OK
  public
  def new_session_token
    return unless rid = _get_request_id  # Enforce token header or fail 412
    token = Rails.cache.fetch(rid,
      expires_in: Rails.configuration.x.relay.new_session_token_timeout) do
        logger.info "Established our token for req #{rid.bytes[0..4]}..."
        RbNaCl::Random.random_bytes 32
    end
    if not token or token.length != 32
      logger.error "(!) NaCl random(32) error:"\
      " len=#{token ? token.length : 'nil'}"
      head :internal_server_error,
        error_details: "Local entropy fail; try again?"
      return
    end
    render text: Base64.strict_encode64(token)
  end

  # Responds with 412, 500 or 200 OK
  def verify_session_token
    # enforce token header or fail 412
    return unless rid = _get_request_id 
    unless (token = Rails.cache.fetch rid)
      logger.info "- request for expired req #{rid.bytes[0..4]}"
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
      logger.warn "(-) handshake '#{body}' => #{e}"
      head :conflict,
        error_details: "Provide session handshake "\
        "(your token XOR our token) as base64 body"
      return
    end

    logger.info "(+) Succesful handshake for req #{rid.bytes[0..4]}"
    # establish session keys

    render text: "#{Base64.strict_encode64 token}\n#{Base64.strict_encode64 xored}"
  end
end