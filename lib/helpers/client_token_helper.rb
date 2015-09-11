require "utils"
require "errors/client_token"

# --- Client token checks --- 
module ClientTokenHelper
  include Utils
  include Errors

  protected
  # check client request token: random 32 bytes
  def _check_client_token(line)
    unless line.length == TOKEN_B64
      fail ClientTokenError.new self,
        client_token: line[0...8],
        msg: "start_session_token, wrong client_token b64 lenth"
    end

    client_token = b64dec line

    unless client_token.length == TOKEN_LEN
      fail ClientTokenError.new self,
        client_token: client_token[0...8],
        msg: "session controller, client_token is not #{TOKEN_LEN} bytes"
    end

    client_token
  end

end