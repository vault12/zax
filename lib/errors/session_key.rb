require "errors/zax_error"
module Errors
  class SessionKeyError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} No session_key/token :prove_hpk\n"\
      "session_key #{dump @data[:session_key]}, "\
      "token #{dumpHex @data[:token]},"\
      "rid #{dumpHex @data[:rid]}"

      @controller.head :precondition_failed, x_error_details:
        "No session_key/token: establish session first"
    end
  end
end