require "utils"
require "response_helper"


class ProofController < ApplicationController
  private
  include Utils
  include ResponseHelper

  KEY_LEN   = 32
  NONCE_LEN = 24
  NONCE_B64 = 32
  KEY_B64   = 44
  CIPHER_B64= 256

  private
  def _get_nonce_time(n)
    nb = n.unpack("C*")[0,8]
    nb.each_index.reduce { |s,i| s + nb[i]*255**(7-i) }
  end

  def _check_nonce(nonce_str)
    nonce = b64dec nonce_str
    raise "Bad nonce: #{dump nonce}" unless nonce and nonce.length==NONCE_LEN
    nt = _get_nonce_time nonce
    raise "Nonce timestamp #{nt} expired by #{Time.now.to_i-nt}" if (Time.now.to_i-nt).abs > Rails.configuration.x.relay.max_nonce_diff
    return nonce
  end

  def _check_session_state
    # report errors with session state
    if @session_key.nil? or @session_key.to_bytes.length!=KEY_LEN or
       @token.nil? or @token.length!=KEY_LEN
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
    lines[0].length==KEY_B64 and lines[1].length==NONCE_B64 and lines[2].length==CIPHER_B64
    return lines
  end

  def _check_client_key(key_line)
    xor_key = b64dec key_line
    return Rails.cache.fetch("client_key_#{@rid}", expires_in: @timeout) do
      key = xor_str xor_key, h2(@token)
      raise "Bad client key: #{dump key}" unless key and key.bytes.length==KEY_LEN
      logger.info "#{INFO_GOOD} Saved client key for req #{@rid.bytes[0..3]}"
      return key
    end
  end

  public
  def prove_hpk
    # Let's see if we got correct request_token
    return unless @rid = _get_request_id

    # Get cached session state
    @timeout = Rails.configuration.x.relay.session_timeout
    @token = Rails.cache.fetch(@rid)
    @session_key = Rails.cache.fetch("key_#{@rid}")
    return unless _check_session_state

    begin
      # masked key 32b = 44b base64
      # nonce 24b = 32b base64
      # ciphertext 192b = 256b base64

      # --- process request body
      body = request.body.read KEY_B64+2+NONCE_B64+2+CIPHER_B64
      lines = _check_body body
      
      # --- first line is client XORed key
      client_key = _check_client_key lines[0]

      # --- get outter nonce
      nonce = _check_nonce lines[1]

      # --- get outter ciphertext
      outer_box = RbNaCl::Box.new(client_key,@session_key)
      inner = JSON.parse outer_box.decrypt(nonce,b64dec(lines[2]))

    rescue RbNaCl::CryptoError => e
      Rails.cache.delete "client_key_#{@rid}"
      logger.error "#{ERROR} Decryption error for packet\n'#{body}'\n#{EXPT} #{e}"
      head :bad_request, error_details: "Decryption error"
      return
    rescue => e
      logger.info "--- #{e.class}"
      Rails.cache.delete "client_key_#{@rid}"
      logger.warn "#{WARN} Aborted prove_hpk key exchange:\n'#{body}'\n#{EXPT} #{e}"
      head :precondition_failed,
        error_details: "Provide masked pub_key, timestamped nonce and signature as 3 lines in base64"
      return
    else
      # Increase timeout on dependents
      Rails.cache.write(@rid, @token, :expires_in => @timeout)
      Rails.cache.write("key_#{@rid}", @session_key, :expires_in => @timeout)
    end

    # PLACEHOLDER
    render text: "#{inner}"
  end
end
