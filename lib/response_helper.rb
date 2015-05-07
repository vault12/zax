require "log_codes"

module ResponseHelper
  include LogCodes

  # Double hash function
  def self.h2(msg)
    RbNaCl::Hash.sha256 "#{RbNaCl::Hash.sha256 msg}#{msg}"
  end

  protected
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

end