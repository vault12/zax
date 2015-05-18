require "log_codes"
require "utils"

module ResponseHelper
  protected
  include LogCodes
  include Utils

  def dump(obj)
    return 'nil' unless obj
    obj.to_s.dump
  end

  def _get_request_id
    begin
      # Let's make sure everything is correct with request_token
      rth = request.headers["HTTP_#{TOKEN}"]
      raise "Missing #{TOKEN} header" unless rth

      rid = b64dec rth
      raise "#{TOKEN} is not 32 bytes" unless rid.length == 32

      return rid

    # Can not get request token: report to log and to client
    rescue => e
      logger.warn "#{INFO_NEG} HTTP_#{TOKEN} (base64):\n"\
      "#{dump rth}:\n#{EXPT} #{e}"
      expires_now
      head :precondition_failed,
        x_error_details: "Provide #{TOKEN} header: 32 bytes (base64)"
    end
    return nil
  end

  def _get_hpk
    begin
      # Let's make sure everything is correct with :hpk
      h = request.headers["HTTP_#{HPK}"]
      raise "Missing #{HPK} header" unless h

      hpk = b64dec h
      raise "#{HPK} is not 32 bytes" unless hpk.length == 32

      return hpk

    # Can not get request token: report to log and to client
    rescue => e
      logger.warn "#{INFO_NEG} bad #{HPK}: #{dump h}\n#{EXPT} #{e}"
      expires_now
      head :bad_request,
        x_error_details: "Provide #{HPK} address to prove ownership as h2 hash in /prove header."
    end
    return nil
  end

  # 8 byte timestamp, MSB first. First 4 bytes will be 0 for a while.
  def _get_nonce_time(n)
    nb = n.unpack("C*")[0,8]
    nb.each_index.reduce { |s,i| s + nb[i]*256**(7-i) }
  end

  def _check_nonce(nonce_str)
    nonce = b64dec nonce_str
    raise "Bad nonce: #{dump nonce}" unless nonce and nonce.length==NONCE_LEN
    nt = _get_nonce_time nonce
    raise "Nonce timestamp #{nt} delta #{Time.now.to_i-nt}" if (Time.now.to_i-nt).abs > Rails.configuration.x.relay.max_nonce_diff
    return nonce
  end

end