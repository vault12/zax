# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

module Errors
  class ClientTokenError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} bad client token\n"\
        "#{@data[:msg]}, client_token = #{dump @data[:client_token]}"
    end
  end
end
