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
    if session_key.nil? or session_key.to_bytes.length!=32 or
       token.nil? or token.length!=32
      logger.warn "'prove_hpk': sk #{dump session_key}, "\
      "tkn #{dump token}, rid #{rid.bytes[0..4]}"
      head :precondition_failed,
        error_details: "No session_key/token: establish session first"
      return
    end

    begin
      # masked key, 32b = 44 base64
      # nonce, 24b = 32 base64
      # ciphertext 
      body = request.body.read 44+2+32
      nl = body.include?("\r\n") ? "\r\n" : "\n"
      lines = body.split nl
      raise "Malformated body" unless lines.count==2 and
        lines[0].length==44 and lines[1].length==32

      # first line is client XORed key
      to = Rails.configuration.x.relay.session_timeout
      xor_key = Base64.strict_decode64 lines[0]
      client_key = Rails.cache.fetch("client_key_#{rid}", expires_in: to) do
        logger.info "#{INFO_GOOD} Saved client key for req #{rid.bytes[0..3]}..."
        key = xor_str xor_key, h2(token)
        raise "Bad client key: #{dump client_key}" unless key and key.bytes.length==32

        nonce = Base64.strict_decode64 lines[1]
        raise "Bad nonce: #{dump nonce}" unless nonce and nonce.length==24
        nt = get_nonce_time nonce
        raise "Nonce timestamp #{nt} expired by #{Time.now.to_i-nt}" if (Time.now.to_i-nt).abs > Rails.configuration.x.relay.max_nonce_diff

        # Increase timeout on dependents and return key
        Rails.cache.write(rid, token, :expires_in => to)
        Rails.cache.write("key_#{rid}", session_key, :expires_in => to)
        key
      end
    rescue => e
      logger.warn "#{WARN} Aborted prove_hpk key exchange: '#{body}' => #{e}"
      head :precondition_failed,
        error_details: "Provide masked pub_key, timestamped nonce and signature as 3 lines in base64"
      return
    end

    # PLACEHOLDER
    render text: "#{Base64.strict_encode64 session_key.public_key.to_bytes}"
  end
end
