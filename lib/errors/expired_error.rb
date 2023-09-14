# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

# Session handshake token expired for the given request_id or
# wasn't created in the first place. Client should start a new handshake

module Errors
  class ExpiredError < ZaxError
    def http_fail
      super
      info "#{INFO_NEG} 'verify' for expired req #{dumpHex @data}"
    end
  end
end
