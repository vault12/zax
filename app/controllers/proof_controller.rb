require "base64"
require "response_helper"

class ProofController < ApplicationController
  private
  include ResponseHelper

  public
  def prove_hpk
    # Let's see if we got correct request_token
    return unless rid = _get_request_id

    # Get cached session state
    token = Rails.cache.fetch(rid)
    session_key = Rails.cache.fetch("key_#{rid}")

    # report errors with session state
    if session_key.nil? or session_key.public_key.to_bytes.length!=32 or
       token.nil? or token.length!=32
      logger.warn "'prove_hpk': sk '#{session_key}', "\
      "tkn '#{token ? token.dump : nil}', rid '#{rid.bytes[0..4]}'"
      head :precondition_failed,
        error_details: "No session_key/token: establish /session first"
      return
    end

    # PLACEHOLDER
    render text: "#{Base64.strict_encode64 session_key.public_key.to_bytes}"
  end
end
