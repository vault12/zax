# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'
module Errors
  class SessionKeyError < ZaxError
    def http_fail
      @response_code = :unauthorized
      super
      warn "#{INFO_NEG} Bad session_key/relay_token/client_token in prove_hpk\n"\
      "session_key #{dump @data[:session_key]}, "\
      "relay_token #{dumpHex @data[:relay_token]}, "\
      "client_token #{dumpHex @data[:client_token]}"
    end
  end
end
