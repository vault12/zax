require "utils"
require "errors/all"

module ResponseHelper
  include Utils
  include Errors

  protected

  # make sure everything is correct with request token header
  def _get_request_id
    rth = request.headers["HTTP_#{TOKEN}"]
    # do we have the token header?
    unless rth
      raise RequestIDError.new(self,rth),
        "Missing #{TOKEN} header"
    end
    # is it correct base64?
    rid = b64dec rth
    # is it correct length?
    unless rid.length == TOKEN_LEN
      raise RequestIDError.new(self,rth),
        "#{TOKEN} is not #{TOKEN_LEN} bytes"
    end
    return rid # good request id
    rescue => e # wrap errors of b64 decode
      raise RequestIDError.new(self,rth), e.message
  end

  # make sure everything is correct with hpk 
  def _get_hpk
    h = request.headers["HTTP_#{HPK}"]
    # do we have hpk header?
    unless h
      raise HPKError.new(self,h),
        "Missing #{HPK} header"
    end
    # correct base64?
    hpk = b64dec h
    unless hpk.length == HPK_LEN
      raise HPKError.new(self,h),
        "#{HPK} is not #{HPK_LEN} bytes"
    end
    return hpk # good hpk (hashed public key)
    rescue => e # wrap errors of b64 decode
      raise HPKError.new(self,h), e.message
  end

  # 8 byte timestamp in 24 byte nonce
  # MSB first; first 4 bytes will be 0 for a while.
  def _get_nonce_time(n)
    nb = n.unpack("C*")[0,8]
    nb.each_index.reduce { |s,i| s + nb[i]*256**(7-i) }
  end

  # check nonce to be withing valid expiration window
  def _check_nonce(nonce_str)
    # TODO: keep nonces in 5 min memcached to prevent
    # replay attack
    nonce = b64dec nonce_str
    raise "Bad nonce: #{dump nonce}" unless nonce and nonce.length==NONCE_LEN
    nt = _get_nonce_time nonce
    if (Time.now.to_i-nt).abs > Rails.configuration.x.relay.max_nonce_diff
      raise "Nonce timestamp #{nt} delta #{Time.now.to_i-nt}"
    end
    return nonce
  end

end