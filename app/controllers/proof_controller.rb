require "base64"
require "response_helper"

class ProofController < ApplicationController
  private
  include ResponseHelper

  private
  def _get_nonce_time(n)
    nb = n.unpack("C*")[0,8]
    nb.each_index.reduce { |s,i| s + nb[i]*255**(7-i) }
  end

  def _check_nonce(nonce_str)
    nonce = Base64.strict_decode64 nonce_str
    raise "Bad nonce: #{dump nonce}" unless nonce and nonce.length==24
    nt = _get_nonce_time nonce
    raise "Nonce timestamp #{nt} expired by #{Time.now.to_i-nt}" if (Time.now.to_i-nt).abs > Rails.configuration.x.relay.max_nonce_diff
    return nonce
  end

  def _check_session_state
    # report errors with session state
    if @session_key.nil? or @session_key.to_bytes.length!=32 or
       @token.nil? or @token.length!=32
      logger.warn "#{INFO_NEG} 'prove_hpk': sk #{dump @session_key}, "\
      "tkn #{dump @token}, rid #{@rid.bytes[0..4]}"
      head :precondition_failed,
        error_details: "No session_key/token: establish session first"
      return nil
    end
    return true # check success
  end

  def _check_body(body)
    raise "No request body" if body.nil? or body.empty?
    nl = body.include?("\r\n") ? "\r\n" : "\n"
    lines = body.split nl
    raise "Malformated body" unless lines.count==3 and
    lines[0].length==44 and lines[1].length==32 and lines[2].length==192
    return lines
  end

  def _check_client_key(key_line)
    to = Rails.configuration.x.relay.session_timeout
    xor_key = Base64.strict_decode64 key_line
    return Rails.cache.fetch("client_key_#{@rid}", expires_in: to) do
      logger.info "#{INFO_GOOD} Saved client key for req #{@rid.bytes[0..3]}"
      key = xor_str xor_key, h2(@token)
      raise "Bad client key: #{dump key}" unless key and key.bytes.length==32
      return key
    end
  end

  public
  def prove_hpk
    # Let's see if we got correct request_token
    return unless @rid = _get_request_id

    # Get cached session state
    @token = Rails.cache.fetch(@rid)
    @session_key = Rails.cache.fetch("key_#{@rid}")
    return unless _check_session_state

    begin
      # masked key, 32b = 44b base64
      # nonce, 24b = 32b base64
      # ciphertext 176b = 192b base64

      # --- process request body
      body = request.body.read 44+2+32+2+192
      lines = _check_body body
      
      # --- first line is client XORed key
      client_key = _check_client_key lines[0]

      # --- get outter nonce
      nonce = _check_nonce lines[1]

      # --- get outter ciphertext
      ct = lines[2]

      # Increase timeout on dependents and return key
      Rails.cache.write(@rid, @token, :expires_in => to)
      Rails.cache.write("key_#{@rid}", session_key, :expires_in => to)

    rescue => e
      Rails.cache.delete "client_key_#{@rid}"
      logger.warn "#{WARN} Aborted prove_hpk key exchange: '#{body}' => #{e}"
      head :precondition_failed,
        error_details: "Provide masked pub_key, timestamped nonce and signature as 3 lines in base64"
      return
    end

    # PLACEHOLDER
    render text: "#{Base64.strict_encode64 session_key.public_key.to_bytes}"
  end
end
