require "log_codes"

module ResponseHelper
  include LogCodes

  TOKEN   = "REQUEST_TOKEN"

  def dump(obj)
    return 'nil' unless obj
    obj.to_s.dump
  end

  protected
  def _get_request_id
    # Let's make sure everything is correct with request_token
    begin
      rth = request.headers["HTTP_#{TOKEN}"]
      raise "Missing #{TOKEN} header" unless rth
      rid = b64dec rth
      raise "#{TOKEN} is not 32 bytes" unless rid.length == 32
      return rid

    # Can not get request token: report to log and to client
    rescue => e
      logger.warn "#{INFO_NEG} HTTP_#{TOKEN} (base64): "\
      "#{ rth ? rth.dump : ''} => #{e}"
      expires_now
      head :precondition_failed,
        error_details: "Provide #{TOKEN} header: 32 bytes (base64)"
    end
    return nil
  end

end