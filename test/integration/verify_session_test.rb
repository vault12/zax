require 'test_helper'

class VerifySessionTest < ActionDispatch::IntegrationTest
  test "verify session token flow" do
    @client_token = RbNaCl::Random.random_bytes 32
    _post "/start_session", @client_token
    _success_response

    body = response.body
    lines = _check_body(body)
    @relay_token = b64dec lines[0]
    h2_client_token = h2(@client_token)

    ### debug
    #ph2_client_token = b64enc h2_client_token
    #print 'h2 client token = ', ph2_client_token; puts
    ### end debug

    client_relay = concat_str(@client_token,@relay_token)
    h2_client_relay = h2(client_relay)

    ### debug
    #ph2_client_relay = b64enc h2_client_relay
    #print 'h2 client relay = ', ph2_client_relay; puts
    ### end debug

    _post "/verify_session", h2_client_token, h2_client_relay
    _success_response

    body = response.body
    lines = _check_body(body)
    skxorct = b64dec lines[0]
    @session_key = xor_str(skxorct,@client_token)
    ### debug
    #print 'session key = ', "#{b64enc @session_key}"; puts
    #print 'session key xor client token = ', lines[0]; puts
    ### end debug
  end
end
