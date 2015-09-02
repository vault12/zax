require "errors/zax_error"

module Errors
  class RelayTokenError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} bad relay token\n"\
      "#{@data[:msg]} where relay token = #{dump @data[:relay_token]}"

      @controller.head :bad_request,
        x_error_details: "Provide correct relay token."
    end
  end
end
