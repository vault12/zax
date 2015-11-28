require 'errors/zax_error'
module Errors
  class TransactionError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} Mailbox Transaction Error: #{dumpHex @data}"
    end
  end
end
