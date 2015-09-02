require "errors/zax_error"
module Errors
  class SessionKeyError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} Bad session_key/relay_token/client_token in prove_hpk\n"\
      "session_key #{dump @data[:session_key]}, "\
      "relay_token #{dumpHex @data[:relay_token]}, "\
      "client_token #{dumpHex @data[:client_token]}"

      @controller.head :precondition_failed, x_error_details:
        "No session_key/relay_token/client_token: establish session first"
    end
  end
end
