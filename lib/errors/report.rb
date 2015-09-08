require "errors/zax_error"

module Errors
  class ReportError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} #{@data[:msg]}"
      @controller.head :bad_request, x_error_details: @data[:msg]
    end
  end
end