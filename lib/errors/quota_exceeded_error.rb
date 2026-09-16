# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

module Errors
  # Raised when a sender hpk's declared live files would exceed max_storage_bytes.
  # Like MailboxFullError, the sender IS deliberately told the specific reason:
  # a legitimate client must react by deleting its own dead uploads or backing
  # off — an indistinguishable 400 provokes session-reconnect storms instead.
  # Only the sender's own aggregate usage is revealed, never other
  # identities' state.
  class QuotaExceededError < ZaxError
    def client_detail
      'Sender storage quota exceeded'
    end
  end
end
