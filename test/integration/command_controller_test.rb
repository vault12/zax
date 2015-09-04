require 'test_helper'

class CommandControllerTest < ActionDispatch::IntegrationTest

  test 'process command 01 count' do
    ### Show that you are simulating hpk correctly
    @chk_key = RbNaCl::PrivateKey.generate
    h2chk = h2(@chk_key.public_key)
    assert_equal(h2chk.length,32)

    hpk = h2(rand_bytes 32)
    assert_equal(hpk.length,32)
    _setup_keys hpk

    to_hpk = RbNaCl::Random.random_bytes(32)
    to_hpk = b64enc to_hpk

    data = {cmd: 'upload', to: to_hpk, payload: 'hello world 0'}
    n = _make_nonce
    _post "/command", hpk, n, _client_encrypt_data(n,data)
    _success_response_empty

    data = {cmd: 'count'}
    n = _make_nonce
    _post "/command", hpk, n, _client_encrypt_data(n,data)
    _success_response

    lines = _check_response(response.body)
    assert_equal(2, lines.length)

    rn = b64dec lines[0]
    rct = b64dec lines[1]
    data = _client_decrypt_data rn,rct

    assert_not_nil data
    assert_includes data, "count"
    assert_equal 0, data['count']
  end

  def _check_response(body)
    raise "No request body" if body.nil?
    nl = body.include?("\r\n") ? "\r\n" : "\n"
    return body.split nl
  end
end
