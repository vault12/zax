# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

module Errors
  class HpkError < ZaxError
    def http_fail
      super
      warn "#{INFO_NEG} hpk error: #{@data[:msg]} #{dump @data[:hpk]}"
    end
  end
end
