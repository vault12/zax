require 'test_helper'

class VerifySessionTest < ActionDispatch::IntegrationTest
  test "verify session token flow" do
    requst_token = b64enc RbNaCl::Random.random_bytes 32
    get "/session", nil, "HTTP_#{TOKEN}": requst_token
    _success_response
    random_token = b64dec response.body
  
    post "/session", nil, "HTTP_#{TOKEN}": (b64enc RbNaCl::Random.random_bytes 32)
    _fail_response :precondition_failed # wrong token

    post "/session", "hello"*100,
      'CONTENT_TYPE':'application/text',
      "HTTP_#{TOKEN}": requst_token
    _fail_response :conflict # handshake mismatch

    post "/session", requst_token,
      'CONTENT_TYPE':'application/text',
      "HTTP_#{TOKEN}": requst_token
    _fail_response :conflict # still wrong handshake

    real_handshake = random_token.bytes.zip((Base64.decode64 requst_token).bytes).map { |a,b| a^b }.pack("C*")

    post "/session", b64enc(real_handshake),
      'CONTENT_TYPE':'application/text',
      "HTTP_#{TOKEN}": requst_token
    _success_response
    pkey = b64dec response.body
    assert_not_empty pkey
  end

end