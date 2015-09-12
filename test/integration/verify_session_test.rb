require 'test_helper'

class VerifySessionTest < ActionDispatch::IntegrationTest
  test "verify session token flow" do
    @client_token = rand_bytes 32
    _post "/start_session", @client_token
    _success_response

    body = response.body
    lines = _check_body(body)
    @relay_token = b64dec lines[0]
    h2_client_token = h2(@client_token)

    # wrong token
    _post "/verify_session", rand_bytes(32), rand_bytes(32)
    _fail_response :bad_request 

    # handshake mismatch
    _post "/verify_session", h2_client_token, "hiii"*8
    _fail_response :conflict

     # handshake mismatch 2
    _post "/verify_session", h2_client_token, h2_client_token
    _fail_response :conflict

    h2_client_relay = h2(@client_token + @relay_token)

    _post "/verify_session", h2_client_token, h2_client_relay
    _success_response

    body = response.body
    lines = _check_body(body)
    skxorct = b64dec lines[0]
    @session_key = xor_str(skxorct,@client_token)
  end
end
