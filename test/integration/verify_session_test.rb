require 'test_helper'

class VerifySessionTest < ActionDispatch::IntegrationTest
  test "verify_session_token in context" do
    requst_token = Base64.strict_encode64 RbNaCl::Random.random_bytes 32
    get "/session", nil, HTTP_REQUEST_TOKEN: requst_token
    _success_response
  
    post "/session", nil, HTTP_REQUEST_TOKEN: (Base64.strict_encode64 RbNaCl::Random.random_bytes 32)
    _fail_response :precondition_failed # wrong token

    post "/session", nil, HTTP_REQUEST_TOKEN: requst_token
    _success_response
  end
end