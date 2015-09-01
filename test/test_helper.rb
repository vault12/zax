ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

require 'response_helper'

class ActiveSupport::TestCase
  include ResponseHelper

  def redisc
    Redis.current
  end

  def redisup
    begin
       redisc.ping
    rescue Errno::ECONNREFUSED => e
       puts "Error: Redis server unavailable. Shutting down..."
       exit 1
    end
  end

  def _fail_response(status)
    assert_response status
    assert_includes(response.headers,"X-Error-Details")
    assert_empty response.body
  end

  def _success_response
    assert_response :success
    assert_not_includes(response.headers,"X-Error-Details")
    assert_not_empty response.body
  end

  def _raw_post(action, params, *lines)
    @request.env['RAW_POST_DATA'] = lines.reduce("") { |s,v| s+="#{b64enc v}\r\n" }
    post action,params
  end

  def _post(route, *lines)
    oneline = ""
    lines.each do |line|
      oneline = oneline.concat "#{b64enc line}\r\n"
    end
    post route, oneline
  end

  def _corrupt_str(str)
    corrupt = str.clone
    corrupt[0] = [corrupt[0].ord+1].pack("C")
    corrupt
  end

  def _test_random_pair
    hpk = Random.new.rand(0..2)
    hpkto = Random.new.rand(0..2)
    if hpk == hpkto
      return true, []
    else
      return false, [hpk,hpkto]
    end
  end

  # get an array with 2 different values
  def _get_random_pair
    values = []
    begin
      values = _test_random_pair
    end while values[0]
    values[1]
  end

  def _setup_token
    @client_token = RbNaCl::Random.random_bytes(32)
    h2_client_token = h2(@client_token)
    Rails.cache.write("client_token_#{h2_client_token}", @client_token, expires_in: @tmout)
  end

  def _check_body(body)
    raise "No request body" if body.nil? or body.empty?
    nl = body.include?("\r\n") ? "\r\n" : "\n"
    return body.split nl
  end

#--------------------------------------------------
#      Used for testing the CommandController
#--------------------------------------------------

  def _setup_keys hpk
    @session_key = RbNaCl::PrivateKey.generate
    @client_key = RbNaCl::PrivateKey.generate

    Rails.cache.write("session_key_#{hpk}",@session_key, :expires_in => @tmout)
    Rails.cache.write("client_key_#{hpk}",@client_key.public_key, :expires_in => @tmout)
  end

  def _send_command(hpk,data)
    n = _make_nonce
    params = {"Content-Type" => "text/plain"}
    _raw_post :process_cmd, params, hpk, n , _client_encrypt_data( n, data)
  end

  def _client_encrypt_data(nonce,data)
    box = RbNaCl::Box.new(@client_key.public_key, @session_key)
    box.encrypt(nonce,data.to_json)
  end

  def _client_decrypt_data(nonce,data)
    box = RbNaCl::Box.new(@client_key.public_key, @session_key)
    JSON.parse box.decrypt(nonce,data)
  end
end
