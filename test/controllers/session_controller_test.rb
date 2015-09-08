require 'test_helper'

class SessionControllerTest < ActionController::TestCase
public

test "new session token" do
  # fail test - no response body
  _raw_post :start_session_token, { }
  _fail_response :bad_request 

  # fail test - 24 instead of 32 bytes
  client_token = rand_bytes 24
  _raw_post :start_session_token, { }, client_token
  _fail_response :bad_request 

  _setup_token
  _raw_post :start_session_token, { }, @client_token
  _success_response
end

test "verify session token" do
  # fail test - no body
  _raw_post :verify_session_token, {}
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
  _fail_response :conflict

  # fail test - random response
  _setup_token
  _raw_post :start_session_token, { }, @client_token
  _raw_post :verify_session_token, {}, h2(@client_token), rand_bytes(32)
  _fail_response :conflict

  # Let's do succesful test
  _setup_token
  _raw_post :start_session_token, { }, @client_token
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
  skxorct = b64dec lines[0]
  session_key = xor_str(skxorct,@client_token)
end
end
