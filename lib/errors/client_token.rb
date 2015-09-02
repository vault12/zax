require "errors/zax_error"

module Errors
  class ClientTokenError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} bad client token\n"\
      "#{@data[:msg]} where client token = #{dump @data[:client_token]}"

      @controller.head :bad_request,
        x_error_details: "Provide client token with 32 random bytes."
    end
  end
end
