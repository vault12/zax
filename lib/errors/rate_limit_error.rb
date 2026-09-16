# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

module Errors
  # Raised when a sender hpk exhausts its fixed-window request budget
  # (config.x.relay.max_requests_per_seconds). Responds with 429 plus a
  # Retry-After header carrying the seconds until the window reopens, so
  # well-behaved clients wait out the budget instead of guessing.
  class RateLimitError < ZaxError
    def initialize(ctrl, data = nil)
      super
      @response_code = :too_many_requests
    end

    def extra_headers
      retry_after = @data.is_a?(Hash) ? @data[:retry_after] : nil
      retry_after ? { retry_after: retry_after.to_s } : {}
    end
  end
end
