# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'utils'
require 'errors/client_token_error'

# --- Client token checks ---
module Helpers
  module ClientTokenHelper
    include Utils
    include Errors

    protected

    # check client request token: random 32 bytes
    def _check_client_token(line)
      unless line.length == TOKEN_B64
        fail ClientTokenError.new self,
          client_token: dumpHex(line),
          msg: "session controller: client_token base64 is not #{TOKEN_B64} bytes"
      end

      client_token = line.from_b64

      unless client_token.length == TOKEN_LEN
        fail ClientTokenError.new self,
          client_token: dumpHex(client_token),
          msg: "session controller: client_token is not #{TOKEN_LEN} bytes"
      end

      client_token
    end

  end
end
