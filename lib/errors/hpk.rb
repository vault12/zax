require "errors/zax_error"
module Errors
  # Can not get HPK: report to log and to client
  class HPKError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} bad #{HPK}"
      @controller.head :bad_request,
        x_error_details: "Provide #{HPK} address to prove ownership as h2 hash in /prove header."
    end
  end
end