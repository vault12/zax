require "utils"
require "errors/hpk"

# --- HPK checks --- 
module HPKHelper
  include Utils
  include Errors

  protected
  # make sure everything is correct with hpk
  def _check_hpk(h)
    unless h.length == HPK_LEN
      raise HPKError.new(self,h),
        "#{HPK} is not #{HPK_LEN} bytes"
    end
  end

  def _get_hpk(h)
    raise HPKError.new(self,h),
      "Missing #{HPK} header" unless h
    hpk = b64dec h  # correct base64?
    _check_hpk hpk
    return hpk # good hpk (hashed public key)
    rescue => e # wrap errors of b64 decode
      raise HPKError.new(self,h), e.message
  end
end