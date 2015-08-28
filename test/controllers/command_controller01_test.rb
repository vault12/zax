class CommandControllerTest < ActionController::TestCase

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

    _send_command hpk, cmd: 'upload', to: to_hpk, payload: 'hello world 0'

    _send_command hpk, cmd: 'count'
    _success_response
    lines = response.body.split "\n"
    assert_equal(2, lines.length)

    rn = b64dec lines[0]
    rct = b64dec lines[1]
    data = _client_decrypt_data rn,rct

    assert_not_nil data
    assert_includes data, "count"
    assert_equal 0, data['count']
    puts data
  end
end
