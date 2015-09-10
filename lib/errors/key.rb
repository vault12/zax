require "errors/zax_error"
module Errors
  class KeyError < ZAXError
    def http_fail
      super
      error "#{ERROR} NaCl error - generate keys; #{data[:msg]}"
      head :internal_server_error, x_error_details: "Can't generate new keys; try again?"
    end
  end
end