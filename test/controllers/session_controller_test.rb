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
  @request.env['RAW_POST_DATA'] = rand_bytes 32
  _fail_response :bad_request

  # fail: 24 instead of 32 bytes
  client_token = rand_bytes 24
  _raw_post :start_session_token, {}, client_token
  _fail_response :bad_request

  _setup_token
  _raw_post :start_session_token, {}, @client_token
  _success_response
  lines = _check_body response.body
  assert_equal(lines.length, 2) # token and difficulty
  assert_equal(Rails.configuration.x.relay.difficulty, lines[1].to_i) # token and difficulty
end

test 'verify session token' do
  # fail test - no body
  _raw_post :verify_session_token, {}
  _fail_response :bad_request

  # fail: wrong encoding
  @request.env['RAW_POST_DATA'] = "#{rand_bytes 32}\r\n#{rand_bytes 32}"
  post :verify_session_token
  _fail_response :bad_request

  # fail test - just 1 line
  _raw_post :verify_session_token, {}, rand_bytes(32)
  _fail_response :bad_request

  # fail test - wrong size line 1
  _raw_post :verify_session_token, {},
    rand_bytes(24), rand_bytes(32)
  _fail_response :bad_request

  # fail test - wrong size line 2
  _raw_post :verify_session_token, {},
    rand_bytes(32), rand_bytes(16)
  _fail_response :bad_request

  # fail test - no such established client_token
  _raw_post :verify_session_token, {},
    rand_bytes(32), rand_bytes(32)
  _fail_response :bad_request

  # fail test - corrupt base64
  @request.env['RAW_POST_DATA'] =
    "#{_corrupt_str(b64enc(rand_bytes(32)),false)}\r\n"\
    "#{b64enc(rand_bytes(32))}\r\n"
  post :verify_session_token,{}
  _fail_response :bad_request

  # fail test - random response
  _setup_token
  _raw_post :start_session_token, { }, @client_token
  _raw_post :verify_session_token, {}, h2(@client_token), rand_bytes(32)
  _fail_response :bad_request

  # Let's do succesful test
  old_diff = Rails.configuration.x.relay.difficulty
  Rails.configuration.x.relay.difficulty = 0

  _setup_token
  _raw_post :start_session_token, {}, @client_token
  _success_response
  body = response.body
  lines = _check_body(body)

  pclient_token = b64enc @client_token
  @relay_token = b64dec lines[0]
  h2_client_token = h2(@client_token)

  client_relay = @client_token + @relay_token
  h2_client_relay = h2(client_relay)

  p1 = "#{b64enc h2_client_token}"
  p2 = "#{b64enc h2_client_relay}"
  plength = p1.length + p2.length
  assert_equal(plength,88)

  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  _success_response
  body = response.body
  lines = _check_body(body)
  sess_key = b64dec lines[0]
  assert_equal Rails.cache.read("session_key_#{h2_client_token}").public_key.to_bytes, sess_key

  Rails.configuration.x.relay.difficulty = old_diff
end

test 'difficulty' do
  # Setup for diff test
  old_diff = Rails.configuration.x.relay.difficulty
  Rails.configuration.x.relay.difficulty = 0

  _setup_token
  _raw_post :start_session_token, {}, @client_token
  _success_response
  body = response.body
  lines = _check_body(body)

  pclient_token = b64enc @client_token
  @relay_token = b64dec lines[0]
  h2_client_token = h2(@client_token)

  client_relay = @client_token + @relay_token
  h2_client_relay = h2(client_relay)

  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  _success_response

  # ----- Diff = 1
  Rails.configuration.x.relay.difficulty = 1
  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  hash = h2(@client_token + @relay_token + h2_client_relay).bytes
  if (hash[0] % 2) > 0
    _fail_response :bad_request
  else
    _success_response
  end

  # ----- Diff = 4
  Rails.configuration.x.relay.difficulty = 4
  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  bt = h2(@client_token + @relay_token + h2_client_relay).bytes[0]
  unless first_zero_bits? bt, 4
    _fail_response :bad_request
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
  Rails.configuration.x.relay.difficulty = 8
  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  unless h2(@client_token + @relay_token + h2_client_relay).bytes[0] == 0
    _fail_response :bad_request
  else
    _success_response
  end

  until h2(@client_token + @relay_token + nonce).bytes[0] == 0
    nonce = RbNaCl::Random.random_bytes 32
  end
  _raw_post :verify_session_token, {}, h2_client_token, nonce
  _success_response

  # ----- Diff = 11
  Rails.configuration.x.relay.difficulty = 11
  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  _fail_response :bad_request

  until array_zero_bits? h2(@client_token + @relay_token + nonce).bytes, 11
    nonce = RbNaCl::Random.random_bytes 32
  end
  _raw_post :verify_session_token, {}, h2_client_token, nonce
  _success_response

  Rails.configuration.x.relay.difficulty = old_diff
end
end
