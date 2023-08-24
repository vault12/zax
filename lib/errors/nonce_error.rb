# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require "errors/zax_error"

module Errors
  class NonceError < ZaxError
    def http_fail
      super
      warn "#{INFO_NEG} Nonce error: \n"\
      "#{@data[:msg]}, nonce = #{dumpHex @data[:nonce]}"
    end
  end
end
