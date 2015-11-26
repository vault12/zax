# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'
module Errors
  class SevereRandomError < ZAXError
    def http_fail
      super
      severe_error 'NaCl error - random(32)'
    end
  end
end
