# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

module Errors
  class ReportError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} #{@data[:msg]}"
    end
  end
end
