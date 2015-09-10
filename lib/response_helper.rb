require "errors/all"
require "helpers/request_body_helper"
require "helpers/client_token_helper"
require "helpers/hpk_helper"
require "helpers/nonce_helper"


module ResponseHelper
  include Errors
  include RequestBodyHelper
  include ClientTokenHelper
  include HPKHelper
  include NonceHelper

  protected
  # === Error reporting ===

  def _report_NaCl_error(e)
    e1 = e.is_a?(RbNaCl::BadAuthenticatorError) ? 'The authenticator was forged or otherwise corrupt' : ''
    e2 = e.is_a?(RbNaCl::BadSignatureError) ? 'The signature was forged or otherwise corrupt' : ''
    logger.error "#{ERROR} Decryption error for packet:\n"\
      "#{e1}#{e2}\n"\
      "#{@body}\n#{EXPT} #{e}"
    head :bad_request, x_error_details: "Decryption error"
  end

end
