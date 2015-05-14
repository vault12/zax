require 'test_helper'

class ProveHpkTest < ActionDispatch::IntegrationTest
  test "prove :hpk" do
    Rails.cache.clear

    # establish handshake
    requst_token = b64enc RbNaCl::Random.random_bytes 32
    get "/session", nil, "HTTP_#{TOKEN}": requst_token
    _success_response
    random_token = b64dec response.body

    real_handshake = random_token.bytes.zip((Base64.decode64 requst_token).bytes).map { |a,b| a^b }.pack("C*")

    post "/session", b64enc(real_handshake),
      'CONTENT_TYPE':'application/text',
      "HTTP_#{TOKEN}": requst_token
    _success_response
    pub_key = b64dec response.body
    assert_not_empty pub_key

    post "/session", b64enc(real_handshake),
      'CONTENT_TYPE':'application/text',
      "HTTP_#{TOKEN}": requst_token
    _success_response
  end
end
