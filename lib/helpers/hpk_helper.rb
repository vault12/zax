# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'utils'
require 'errors/hpk_error'

# --- HPK checks ---
module Helpers
  module HpkHelper
    include Utils
    include Errors

    protected
    # make sure everything is correct with hpk
    def _check_hpk(h)
      unless h.length == HPK_LEN
        raise HPKError.new self, { hpk: h, msg: "HPK is not #{HPK_LEN} bytes" }
      end
    end

    def _get_hpk(h)
      raise HPKError.new(self, { hpk: h, msg: "_get_hpk: Missing HPK" } ) unless h
      hpk = h.from_b64  # correct base64?
      _check_hpk hpk
      return hpk # good hpk (hashed public key)
      rescue => e # wrap errors of b64 decode
        raise HPKError.new self, { hpk: h, msg: e.message }
    end
  end
end
