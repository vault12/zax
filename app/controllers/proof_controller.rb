require "response_helper"

class ProofController < ApplicationController
  private
  include ResponseHelper

  CIPHER_B64 = 256

  def _check_session_state
    # report errors with session state
    if @session_key.nil? or @session_key.to_bytes.length!=KEY_LEN or
       @token.nil? or @token.length!=KEY_LEN
      logger.warn "#{INFO_NEG} No session_key/token :prove_hpk\n"\
      "sk #{dump @session_key}, "\
      "tkn #{dump @token}, rid #{@rid.bytes[0..4]}"
      head :precondition_failed,
        x_error_details: "No session_key/token: establish session first"
      return nil
    end
    return true # check success
  end

  def _check_body(body)
    raise "No request body" if body.nil? or body.empty?
    nl = body.include?("\r\n") ? "\r\n" : "\n"
    lines = body.split nl
    raise "Malformated body" unless lines.count==3 and
      lines[0].length==KEY_B64 and
      lines[1].length==NONCE_B64 and
      lines[2].length==CIPHER_B64
    return lines
  end

  def _check_client_key(key_line)
    xor_key = b64dec key_line
    key = xor_str xor_key, h2(@token)
    raise "Bad client key: #{dump key}" unless 
      key and key.bytes.length==KEY_LEN
    return key
  end

  public
  # --- "/prove [X_HPK]" ---
  def prove_hpk
    # Get basic request data
    return unless @rid = _get_request_id
    return unless @hpk = _get_hpk

    # If we already have session key, we keep it
    # for timeout duration, no overwrites
    if Rails.cache.fetch("client_key_#{@hpk}") then
      return render text:"202 OK", status: :accepted
    end

    # Get cached session state
    @timeout = Rails.configuration.x.relay.session_timeout
    @token = Rails.cache.fetch(@rid)
    @session_key = Rails.cache.fetch("key_#{@rid}")
    return unless _check_session_state

    # POST lines:
    #  masked client session key 32b = 44b base64
    #  nonce 24b = 32b base64
    #  ciphertext 192b = 256b base64
    begin
      # --- process request body
      body = request.body.read KEY_B64+2+NONCE_B64+2+CIPHER_B64
      lines = _check_body body
      
      # --- first line is masked client session key
      client_key = _check_client_key lines[0]

      # --- get outter nonce
      nonce = _check_nonce lines[1]

      # --- get outter ciphertext
      outer_box = RbNaCl::Box.new(client_key,@session_key)
      inner = JSON.parse outer_box.decrypt(nonce,b64dec(lines[2]))
      inner = Hash[ inner.map { |k,v| [k.to_sym,b64dec(v)] } ]

      # inner box with node permanent comm_key (identity)
      inner_box = RbNaCl::Box.new(inner[:pub_key],@session_key)

      # prove decryption with client comm_key
      sign  = inner_box.decrypt(inner[:nonce],inner[:ctext])
      sign2 = xor_str h2(@rid), h2(@token)
      raise "Signature mis-match" unless sign and sign2 and sign == sign2
      raise "HPK mismatch" unless @hpk == h2(inner[:pub_key])

    rescue RbNaCl::CryptoError => e
      logger.error "#{ERROR} Decryption error for packet:\n"\
        "#{ e.is_a?(RbNaCl::BadAuthenticatorError) ? 'The authenticator was forged or otherwise corrupt' : ''}"\
        "#{ e.is_a?(RbNaCl::BadSignatureError) ? 'The signature was forged or otherwise corrupt' : ''}"\
        "\n#{body}\n#{EXPT} #{e}"
      head :bad_request, x_error_details: "Decryption error"
      return

    rescue => e
      logger.warn "#{WARN} Aborted prove_hpk key exchange:\n"\
        "#{body}\n#{EXPT} #{e}"
      head :precondition_failed,
        x_error_details: "Provide masked pub_key, timestamped nonce and signature as 3 lines in base64"
      return
    else
      # Increase timeout on dependents
      Rails.cache.write(@rid, @token, expires_in: @timeout)
      Rails.cache.write("key_#{@rid}", @session_key, expires_in: @timeout)
      Rails.cache.write("client_key_#{@hpk}", client_key, expires_in: @timeout)
      logger.info "#{INFO_GOOD} Saved client session key for hpk #{b64enc @hpk}"
      
      render text:"200 OK", status: :ok
    end
  end
end
