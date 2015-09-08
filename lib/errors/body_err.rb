require "errors/zax_error"

module Errors
  class BodyError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} bad request body\n"\
        "#{@data[:msg]}: '#{@data[:body]}', #{@data[:lines]} line(s)"
      @controller.head :bad_request,
        x_error_details: "Request BODY does not match this request specification"
    end
  end
end
