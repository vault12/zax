# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

module Errors
  # Raised when a recipient mailbox is already at its max_messages ceiling.
  # Unlike most relay errors, the sender IS told the specific reason so a
  # legitimate client can back off and retry later instead of failing blindly.
  # This intentionally reveals only aggregate destination fullness to the sender
  # — never message contents, senders, or any other mailbox metadata.
  class MailboxFullError < ZaxError
    def client_detail
      'Destination mailbox is full'
    end
  end
end
