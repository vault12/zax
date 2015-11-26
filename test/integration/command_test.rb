# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'
require 'prove_test_helper'

class CommandTest < ProveTestHelper
  test "prove and upload" do
    hpk = setup_prove
    _setup_keys hpk
    to_hpk = RbNaCl::Random.random_bytes(32)
    to_hpk = b64enc to_hpk
    data = {cmd: 'upload', to: to_hpk, payload: 'hello world 0'}
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response_empty
  end

  test 'nonce repeat rejection' do
    hpk = setup_prove
    _setup_keys hpk
    to_hpk = RbNaCl::Random.random_bytes(32)
    to_hpk = b64enc to_hpk
    data = {cmd: 'upload', to: to_hpk, payload: 'hello world 1'}
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response_empty

    data = {cmd: 'upload', to: to_hpk, payload: 'hello world 2'}
    _post '/command', hpk, n, _client_encrypt_data(n, data) # nonce re-used
    _fail_response :bad_request # failed - nonce not unique in time window
  end
end
