# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class CommandControllerTest < ActionDispatch::IntegrationTest

  test 'process basic commands' do
    ### Use hpk to upload, check and delete message
    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk

    to_key = RbNaCl::PrivateKey.generate
    to_hpk = h2(to_key.public_key)

    ### Upload
    msg_nonce = rand_bytes(24).to_b64
    msg_data = {
      cmd: 'upload',
      to: to_hpk.to_b64,
      payload: {
        ctext: 'hello world 0',
        nonce: msg_nonce
      }
    }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    msg_token = b64dec _success_response # 32 byte storage token for the message
    assert_equal(32, msg_token.length)

    ### Count

    data = {cmd: 'count'}
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response

    lines = _check_response(response.body)
    assert_equal(2, lines.length)

    rn = lines[0].from_b64
    rct = lines[1].from_b64
    data = _client_decrypt_data rn, rct

    assert_not_nil data
    assert_equal 0, data

    ### Download

    data = {cmd: 'download'}
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response

    lines = _check_response(response.body)
    assert_equal(2, lines.length)

    rn = lines[0].from_b64
    rct = lines[1].from_b64
    data = _client_decrypt_data rn, rct

    assert_not_nil data
    assert_equal data.length, 0

    ### Message status

    data = { cmd: 'messageStatus', token: msg_token.to_b64 }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    r = _success_response
    assert_operator r.to_i, :>, 0

    ### Delete
    _setup_keys to_hpk  # Now a session for dest mailbox
    data = { cmd: 'delete', payload: [msg_nonce]}
    n = _make_nonce
    _post '/command', to_hpk, n, _client_encrypt_data(n, data)
    _success_response

    ### Message is now deleted
    _setup_keys hpk
    data = { cmd: 'messageStatus', token: msg_token.to_b64 }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    r = _success_response
    assert_equal r,'-2'  # -2 is redis missing key

    ### Misc commands: entropy
    data = { cmd: 'getEntropy', size: 1000 }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    data = JSON.parse _success_response.from_b64, symbolize_names:true
    assert_not_nil data
    assert_not_nil data[:entropy]
    assert_equal 1000, data[:entropy].from_b64.length
  end

  test 'process command guards' do
    hpk = h2(rand_bytes 32)
    assert_equal(hpk.length,32)
    _setup_keys hpk

    _post '/command', hpk
    _fail_response :bad_request # no body

    _post '/command', hpk, '123'
    _fail_response :bad_request # short body

    bad_nonce = rand_bytes 24
    _post '/command', hpk, bad_nonce
    _fail_response :bad_request # short body

    bad_nonce = rand_bytes 24
    _post '/command', hpk, bad_nonce, '123'
    _fail_response :bad_request # short body

    old_nonce = _make_nonce((Time.now - 2.minutes).to_i)
    _post '/command', hpk, old_nonce
    _fail_response :bad_request # expired nonce

    _post '/command', hpk, _make_nonce, '456'
    _fail_response :bad_request # bad text

    corrupt = _corrupt_str(_client_encrypt_data( _make_nonce, {cmd: 'count'}))
    _post '/command', hpk, _make_nonce, corrupt
    _fail_response :bad_request # corrupt ciphertext
  end

  test 'loosing session keys results in HTTP 401' do
    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk

    to_key = RbNaCl::PrivateKey.generate
    to_hpk = h2(to_key.public_key)

    ### Upload
    msg_nonce = rand_bytes(24).to_b64
    msg_data = {
      cmd: 'upload',
      to: to_hpk.to_b64,
      payload: {
        ctext: 'hello world HTTP 401 test',
        nonce: msg_nonce
      }
    }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    msg_token = b64dec _success_response # 32 byte storage token for the message
    assert_equal(32, msg_token.length) # Works as expected

    ### Redis restart lost all keys
    _delete_keys hpk
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    _fail_response :unauthorized # Keys are lost => 401 Unauthorized
  end

end
