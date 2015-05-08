require 'test_helper'

class ProveHpkTest < ActionDispatch::IntegrationTest
  test "prove :hpk" do
    # establish handshake
    requst_token = Base64.strict_encode64 RbNaCl::Random.random_bytes 32
    get "/session", nil, HTTP_REQUEST_TOKEN: requst_token
    _success_response
    random_token = Base64.strict_decode64 response.body

    real_handshake = random_token.bytes.zip((Base64.decode64 requst_token).bytes).map { |a,b| a^b }.pack("C*")

    post "/session", Base64.strict_encode64(real_handshake),
      'CONTENT_TYPE':'application/text',
      'HTTP_REQUEST_TOKEN': requst_token
    _success_response
    pub_key = Base64.strict_decode64 response.body
    assert_not_empty pub_key

    post "/session", Base64.strict_encode64(real_handshake),
      'CONTENT_TYPE':'application/text',
      'HTTP_REQUEST_TOKEN': requst_token
    _success_response

    n = _client_nonce
    
  end
end
