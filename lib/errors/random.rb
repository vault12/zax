require "errors/zax_error"
module Errors
  # Can not get HPK: report to log and to client
  class RandomError < ZAXError
    def http_fail
      super
      error "#{ERROR} NaCl error- random(32)"
      @controller.head :internal_server_error, x_error_details: "Local RNG fail; try again?"
    end
  end
end