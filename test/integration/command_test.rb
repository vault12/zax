require 'test_helper'
require 'prove_test_helper'

class CommandTest < ProveTestHelper
  test "session, prove hpk, command token flow" do
    hpk = setup_prove
    _setup_keys hpk
    to_hpk = RbNaCl::Random.random_bytes(32)
    to_hpk = b64enc to_hpk
    data = {cmd: 'upload', to: to_hpk, payload: 'hello world 0'}
    n = _make_nonce
    _post "/command", hpk, n, _client_encrypt_data(n,data)
  end
end
