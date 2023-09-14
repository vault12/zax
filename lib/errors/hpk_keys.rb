# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

# There are no saved HPK client/session keys
# Client should prove HPK ownership to establish these keys

module Errors
  class HpkKeys < ZaxError
    def http_fail
      @response_code = :unauthorized
      super
      warn "#{WARN} key/client_key not found for process command - hpk: #{dumpHex @data[:hpk]}"
    end
  end
end
