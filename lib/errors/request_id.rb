require "errors/zax_error"

module Errors
  # Can not get request token: report to log and to client
  class RequestIDError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} HTTP_#{TOKEN} (base64)"
      @controller.head :precondition_failed,
      x_error_details: "Provide #{TOKEN} header: 32 bytes (base64)"
    end
  end
end