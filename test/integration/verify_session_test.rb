require 'test_helper'

class VerifySessionTest < ActionDispatch::IntegrationTest
  test "verify session token flow" do
    requst_token = Base64.strict_encode64 RbNaCl::Random.random_bytes 32
    get "/session", nil, HTTP_REQUEST_TOKEN: requst_token
    _success_response
    random_token = Base64.strict_decode64 response.body
  
    post "/session", nil, HTTP_REQUEST_TOKEN: (Base64.strict_encode64 RbNaCl::Random.random_bytes 32)
    _fail_response :precondition_failed # wrong token

    post "/session", "hello"*100,
      'CONTENT_TYPE':'application/text',
      'HTTP_REQUEST_TOKEN': requst_token
    _fail_response :conflict # handshake mismatch

    post "/session", requst_token,
      'CONTENT_TYPE':'application/text',
      'HTTP_REQUEST_TOKEN': requst_token
    _fail_response :conflict # still wrong handshake

    real_handshake = random_token.bytes.zip((Base64.decode64 requst_token).bytes).map { |a,b| a^b }.pack("C*")

    post "/session", Base64.strict_encode64(real_handshake),
      'CONTENT_TYPE':'application/text',
      'HTTP_REQUEST_TOKEN': requst_token
    _success_response
    pkey = Base64.strict_decode64 response.body
    assert_not_empty pkey
  end

  
end