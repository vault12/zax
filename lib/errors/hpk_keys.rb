# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

# There are no saved HPK client/session keys
# Client should prove HPK ownership to establish these keys

module Errors
  class HpkKeys < ZaxError
    # A command for an hpk with no live session: expired, lost to a relay
    # restart, or never proven
    def reason
      'NoSession'
    end

    def http_fail
      # respond with the SAME :bad_request a decryption failure yields.
      super
      warn "#{WARN} key/client_key not found for process command - hpk: #{dumpHex @data[:hpk]}"
    end
  end
end
