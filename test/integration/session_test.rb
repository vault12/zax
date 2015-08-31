require 'test_helper'

class VerifySessionTest < ActionDispatch::IntegrationTest
  test "verify session token flow 01" do

    post "/start_session", nil
    _fail_response :internal_server_error # wrong token

    @client_token = RbNaCl::Random.random_bytes 32
    _post "/start_session", @client_token
    _success_response

    @client_token = RbNaCl::Random.random_bytes 31
    _post "/start_session", @client_token
    _fail_response :internal_server_error # wrong token

    @client_token = b64enc RbNaCl::Random.random_bytes 32
    _post "/start_session", @client_token
    _fail_response :internal_server_error

    _post "/start_session", "hello vault12"
    _fail_response :internal_server_error

    @client_token = RbNaCl::Random.random_bytes 32
    _post "/start_session", @client_token
    _success_response
    pkey = b64dec response.body
    assert_not_empty pkey
  end
end
