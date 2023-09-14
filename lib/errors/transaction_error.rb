# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

require 'errors/zax_error'
module Errors
  class TransactionError < ZaxError
    def http_fail
      @response_code = :internal_server_error
      warn "#{INFO_NEG} Redis transaction error, hpk #{MAGENTA}#{dumpHex @data[:hpk]}#{ENDCLR}"
      super
    end
  end
end
