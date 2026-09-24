# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'errors/zax_error'

module Errors
  # Raised when startFileUpload declares a file_size over max_file_size.
  # Like QuotaExceededError, the sender IS deliberately told the specific
  # reason: it already knows the size it declared, the cap itself is public
  # in the relay sources, and only a client that can tell this rejection
  # from any other 400 can react sensibly — tell the user the file cannot
  # go through this relay instead of showing a generic error and reporting
  # nothing. Nothing about other identities' state is revealed.
  class FileSizeLimitError < ZaxError
    def client_detail
      'File size over relay limit'
    end
  end
end
