# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class SessionControllerTest < ActionController::TestCase
public

test 'new session token' do
  # fail: no response body
  _raw_post :start_session_token, {}
  _fail_response :bad_request

  # fail: wrong encoding
  @request.env['RAW_POST_DATA'] = "\xCF:D\x15\xD8\xE3!\xD5{\x17\xF6\xADL$\xD7\xAB\x13\xEC\xF3r\xE4\x8A\xC3\x95v\x02\x9E\xB2\xC4N\xF3h"
  post :start_session_token, params: {}
  _fail_response :unauthorized

  # fail: 24 instead of 32 bytes
  client_token = rand_bytes 24
  _raw_post :start_session_token, {}, client_token
  _fail_response :unauthorized

  _setup_token
  _raw_post :start_session_token, {}, @client_token
  _success_response
  lines = _check_body response.body
  assert_equal(lines.length, 2) # token and difficulty
  assert_equal(get_diff, lines[1].to_i) # token and difficulty
end

test 'verify session token' do
  # fail test - no body
  _raw_post :verify_session_token, {}
  _fail_response :bad_request

  # fail: wrong encoding
  @request.env['RAW_POST_DATA'] = "#{rand_bytes 32}\r\n#{rand_bytes 32}"
  post :verify_session_token
  _fail_response :unauthorized

  # fail test - just 1 line
  _raw_post :verify_session_token, {}, rand_bytes(32)
  _fail_response :bad_request

  # fail test - wrong size line 1
  _raw_post :verify_session_token, {},
    rand_bytes(24), rand_bytes(32)
  _fail_response :unauthorized

  # fail test - wrong size line 2
  _raw_post :verify_session_token, {},
    rand_bytes(32), rand_bytes(16)
  _fail_response :bad_request

  # fail test - no such established client_token
  _raw_post :verify_session_token, {},
    rand_bytes(32), rand_bytes(32)
  _fail_response :unauthorized

  # fail test - corrupt base64
  @request.env['RAW_POST_DATA'] =
    "#{_corrupt_str(rand_bytes(32).to_b64,false)}\r\n"\
    "#{rand_bytes(32).to_b64}\r\n"
  post :verify_session_token,{}
  _fail_response :bad_request

  # fail test - random response
  _setup_token
  _raw_post :start_session_token, { }, @client_token
  _raw_post :verify_session_token, {}, h2(@client_token), rand_bytes(32)
  _fail_response :unauthorized

  # Let's do succesful test
  old_diff = get_diff
  set_diff 0

  _setup_token
  _raw_post :start_session_token, {}, @client_token
  _success_response
  body = response.body
  lines = _check_body(body)

  pclient_token = @client_token.to_b64
  @relay_token = lines[0].from_b64
  h2_client_token = h2(@client_token)

  client_relay = @client_token + @relay_token
  h2_client_relay = h2(client_relay)

  p1 = "#{h2_client_token.to_b64}"
  p2 = "#{h2_client_relay.to_b64}"
  plength = p1.length + p2.length
  assert_equal(plength,88)

  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  _success_response
  body = response.body
  lines = _check_body(body)
  sess_key = lines[0].from_b64
  assert_equal Rails.cache.read("session_key_#{h2_client_token}").public_key.to_bytes, sess_key

  set_diff old_diff
end

test 'difficulty' do
  # Setup for diff test
  old_diff = get_diff
  set_diff 0

  _setup_token
  _raw_post :start_session_token, {}, @client_token
  _success_response
  body = response.body
  lines = _check_body(body)

  pclient_token = @client_token.to_b64
  @relay_token = lines[0].from_b64
  h2_client_token = h2(@client_token)

  client_relay = @client_token + @relay_token
  h2_client_relay = h2(client_relay)

  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  _success_response

  # Disable throttling for this test
  save_period = Rails.configuration.x.relay.period
  Rails.configuration.x.relay.period = 0

  # ----- Diff = 1
  set_diff 1
  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  hash = h2(@client_token + @relay_token + h2_client_relay).bytes
  if (hash[0] % 2) > 0
    _fail_response :unauthorized
  else
    _success_response
  end

  # ----- Diff = 4
  set_diff 4
  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  bt = h2(@client_token + @relay_token + h2_client_relay).bytes[0]
  unless first_zero_bits? bt, 4
    _fail_response :unauthorized
  else
    _success_response
  end

  nonce = RbNaCl::Random.random_bytes 32
  until first_zero_bits? h2(@client_token + @relay_token + nonce).bytes[0], 4
    nonce = RbNaCl::Random.random_bytes 32
  end
  _raw_post :verify_session_token, {}, h2_client_token, nonce
  _success_response

  # ----- Diff = 8
  set_diff 8
  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  unless h2(@client_token + @relay_token + h2_client_relay).bytes[0] == 0
    _fail_response :unauthorized
  else
    _success_response
  end

  until h2(@client_token + @relay_token + nonce).bytes[0] == 0
    nonce = RbNaCl::Random.random_bytes 32
  end
  _raw_post :verify_session_token, {}, h2_client_token, nonce
  _success_response

  # ----- Diff = 11
  set_diff 11
  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  _fail_response :unauthorized

  until array_zero_bits? h2(@client_token + @relay_token + nonce).bytes, 11
    nonce = RbNaCl::Random.random_bytes 32
  end
  _raw_post :verify_session_token, {}, h2_client_token, nonce
  _success_response

  set_diff old_diff

  # restore throttle
  Rails.configuration.x.relay.period = save_period
end
end
