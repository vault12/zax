require "errors/zax_error"

# Can not get HPK from header

module Errors
  class HPKError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} bad #{HPK}"
      @controller.head :bad_request,
        x_error_details: "Provide #{HPK} address to prove ownership as h2 hash in /prove header."
    end
  end
end