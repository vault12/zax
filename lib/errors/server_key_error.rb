# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'
module Errors
  class ServerKeyError < ZaxError
    def http_fail
      # Set the 500 BEFORE super so super renders it; severe_error's performed?
      # guard then only logs. Without this, super rendered the default 400 and
      # the guard suppressed the intended 500
      @response_code = :internal_server_error
      super
      severe_error 'NaCl key generation error'
    end
  end
end
