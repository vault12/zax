require "errors/zax_error"

# There are no saved HPK client/session keys saved
# Client should prove HPK ownership to establish these keys

module Errors
  class HPK_keys < ZAXError
    def http_fail
      super
      warn "#{WARN} key/client_key not found for process command - hpk: #{dumpHex @data}"
      @controller.head :precondition_failed,
        x_error_details: "Prove your ownership of HPK before sending relay commands"
    end
  end
end