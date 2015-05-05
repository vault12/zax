require "base64"

class SessionController < ApplicationController

  # Responds with 412, 500 or 200 OK
  def new_session_token
    return unless rid = get_request_id
    token = RbNaCl::Random.random_bytes 32
    if not token or token.length != 32
      logger.error "RbNaCl::Random.random_bytes(32) fail: length #{token ? token.length : 'nil'}"
      head :internal_server_error, error_details: "Failed to generate local entropy, try again?"
      return
    end
    Rails.cache.fetch(rid, expires_in: Rails.configuration.relay[:new_session_token_timeout]) do
      logger.info "Established token for rid #{rid.bytes}"
      token
    end
    render text: Base64.strict_encode64(token)
  end

  # Responds with 412, 500 or 200 OK
  def verify_session_token
    return unless rid = get_request_id
    unless (token = Rails.cache.fetch rid)
      logger.info "Verify request for expired request_id #{rid}"
      head :precondition_failed,
           error_details: "Your REQUEST_TOKEN expired after #{Rails.configuration.relay[:new_session_token_timeout]} seconds"
      return
    end
    xored = token.bytes.zip(rid.bytes).map { |a,b| a^b }.pack("C*")
    render text: "#{Base64.strict_encode64 token}\n#{Base64.strict_encode64 xored}"
  end

  private
  def get_request_id
    begin
      raise "Missing REQUEST_TOKEN header" unless request.headers["HTTP_REQUEST_TOKEN"]
      rid = Base64.strict_decode64 request.headers["HTTP_REQUEST_TOKEN"]
      raise "REQUEST_TOKEN is not 32 bytes" unless rid.length == 32
      return rid
    rescue => e
      logger.warn "decode64 HTTP_REQUEST_TOKEN: '#{request.headers["HTTP_REQUEST_TOKEN"]}' => #{e}"
      head :precondition_failed, error_details: "Provide REQUEST_TOKEN header: 32 bytes, base64 encoded."
    end
    return nil
  end

end