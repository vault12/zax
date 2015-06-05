require "errors/zax_error"
module Errors
  class SessionKeyError < ZAXError
    def http_fail
      super
      warn "#{INFO_NEG} Bad session_key/token/rid in prove_hpk()\n"\
      "session_key #{dump @data[:session_key]}, "\
      "token #{dumpHex @data[:token]},"\
      "rid #{dumpHex @data[:rid]}"

      @controller.head :precondition_failed, x_error_details:
        "No session_key/token/request_id: establish session first"
    end
  end
end