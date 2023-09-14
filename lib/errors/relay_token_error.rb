# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

module Errors
  class RelayTokenError < ZaxError
    def http_fail
      super
      warn "#{INFO_NEG} bad relay token\n"\
      "#{@data[:msg]} where relay token = #{dump @data[:relay_token]}"
    end
  end
end
