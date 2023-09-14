# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

module Errors
  class BodyError < ZaxError
    def http_fail
      super
      warn "#{INFO_NEG} bad request body\n"\
        "#{@data[:msg]}: '#{@data[:body]}', #{@data[:lines]} line(s)"

      # Inform client about formatting errors, body check
      # is procesed before accessing relay internal state.
      @controller.head :bad_request,
        x_error_details: 'Request BODY does not match this request specification'
    end
  end
end
