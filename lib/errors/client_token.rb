require "errors/zax_error"

# Can not get HPK from header

module Errors
  class ClientTokenError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} bad #{CLIENT_TOKEN}"
      @controller.head :bad_request,
        x_error_details: "Provide #{CLIENT_TOKEN} with 32 random bytes."
    end
  end
end
