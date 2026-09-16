# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

module Errors
  # Raised when the relay-wide request ceiling for the crypto-heavy handshake
  # path (config.x.relay.max_global_requests_per_seconds) is exceeded. Responds
  # with 503 so clients treat it as transient relay overload and retry later —
  # distinct from a per-hpk 429. Reveals only aggregate busyness, no per-caller
  # state, so the specific "busy" detail is safe to return.
  class GlobalLimitError < ZaxError
    def initialize(ctrl, data = nil)
      super
      @response_code = :service_unavailable
    end

    def client_detail
      'Relay is busy, retry later'
    end
  end
end
