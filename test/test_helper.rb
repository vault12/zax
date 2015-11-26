# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

require 'response_helper'
require 'minitest/reporters'

Minitest::Reporters.use!

class ActiveSupport::TestCase
  include ResponseHelper

  def rds
    Redis.current
  end

  def redisup
    begin
       rds.ping
    rescue Errno::ECONNREFUSED => e
       puts 'Error: Redis server unavailable. Shutting down...'
       exit 1
    end
  end

  def _fail_response(status)
    assert_response status
    assert_includes(response.headers, 'X-Error-Details')
    assert_empty response.body
  end

  def _success_response_empty
    assert_response :success
    assert_not_includes(response.headers, 'X-Error-Details')
    assert_empty response.body
  end

  def _success_response
    assert_response :success
    assert_not_includes(response.headers, 'X-Error-Details')
    assert_not_empty response.body
  end

  def _encode_lines(lines)
    lines.reduce('') { |s,l| s+="#{b64enc l}\r\n" }
  end

  def _raw_post(action, params, *lines)
    @request.env['RAW_POST_DATA'] = _encode_lines lines
    post action, params
  end

  def _post(route, *lines)
    post route, _encode_lines(lines)
  end

  def _corrupt_str(str, minor = true)
    corrupt = str.clone
    l = str.length
    corruption = minor ? 1 : l / 5
    (0...corruption).each do
      idx = rand l
      shift = minor ? 1 : rand(128)
      corrupt[idx] = [(corrupt[idx].ord+shift) % 256 ].pack('C')
    end
    corrupt
  end

  def _test_random_pair(top)
    hpk = Random.new.rand(0..top)
    hpkto = Random.new.rand(0..top)
    if hpk == hpkto
      return true, []
    else
      return false, [hpk, hpkto]
    end
  end

  # get an array with 2 different values where
  # top is the top number in the set starting at zero
  def _get_random_pair(top)
    values = []
    begin
      values = _test_random_pair(top)
    end while values[0]
    values[1]
  end

  def _setup_token
    @client_token = RbNaCl::Random.random_bytes(32)
    h2_client_token = h2(@client_token)
    Rails.cache.write("client_token_#{h2_client_token}", @client_token, expires_in: @tmout)
  end

#--------------------------------------------------
#      Used for testing the CommandController
#--------------------------------------------------

  def _setup_keys hpk
    @session_key = RbNaCl::PrivateKey.generate
    _client_key = RbNaCl::PrivateKey.generate
    @client_key = _client_key.public_key

    Rails.cache.write("session_key_#{hpk}",@session_key, :expires_in => @tmout)
    Rails.cache.write("client_key_#{hpk}",@client_key, :expires_in => @tmout)
  end

  def _send_command(hpk,data)
    n = _make_nonce
    params = {'Content-Type' => 'text/plain'}
    _raw_post :process_cmd, params, hpk, n , _client_encrypt_data( n, data)
  end

  def _client_encrypt_data(nonce,data)
    box = RbNaCl::Box.new(@client_key, @session_key)
    box.encrypt(nonce,data.to_json)
  end

  def _client_decrypt_data(nonce,data)
    box = RbNaCl::Box.new(@client_key, @session_key)
    ptext = box.decrypt(nonce,data)
    JSON.parse ptext
    # Strict JSON parsing does not accept plain text numbers
    rescue JSON::ParserError
      ptext ? ptext.to_i : nil
  end
end
