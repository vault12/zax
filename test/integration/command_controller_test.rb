# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class CommandControllerTest < ActionDispatch::IntegrationTest

  test 'process command 01 count' do
    ### Show that you are simulating hpk correctly
    @chk_key = RbNaCl::PrivateKey.generate
    h2chk = h2(@chk_key.public_key)
    assert_equal(h2chk.length, 32)

    hpk = h2(rand_bytes 32)
    assert_equal(hpk.length, 32)
    _setup_keys hpk

    to_hpk = RbNaCl::Random.random_bytes(32)
    to_hpk = b64enc to_hpk

    ### Upload

    data = {cmd: 'upload', to: to_hpk, payload: 'hello world 0'}
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response_empty

    ### Count

    data = {cmd: 'count'}
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response

    lines = _check_response(response.body)
    assert_equal(2, lines.length)

    rn = b64dec lines[0]
    rct = b64dec lines[1]
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

    rn = b64dec lines[0]
    rct = b64dec lines[1]
    data = _client_decrypt_data rn, rct

    assert_not_nil data
    assert_equal data.length, 0

    ### Delete

    data = {cmd: 'delete', payload: []}
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response
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

  def _check_response(body)
    fail BodyError.new self, msg: 'No request body' if body.nil?
    nl = body.include?("\r\n") ? "\r\n" : "\n"
    return body.split nl
  end
end
