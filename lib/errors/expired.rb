require "errors/zax_error"

# Session handshake token expired for given request_id or 
# wasn't created in first place. Client should start new handshake 

module Errors
  class ExpiredError < ZAXError
    def http_fail
      super
      info "#{INFO_NEG} 'verify' for expired req #{dumpHex @data[0..7]}"
      @controller.head :precondition_failed,
        x_error_details: "Your #{TOKEN} expired after #{Rails.configuration.x.relay.token_timeout} seconds. Start new session."
    end
  end
end