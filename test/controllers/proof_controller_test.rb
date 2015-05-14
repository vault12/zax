require 'test_helper'
require "utils"

class ProofControllerTest < ActionController::TestCase
  include Utils

  test "prove_hpk guard conditions" do
    Rails.cache.clear

    # random hpk for first basic tests
    hpk = b64enc h2(RbNaCl::Random.random_bytes 32)
    head :prove_hpk, hpk: hpk
    _fail_response :precondition_failed # no header

    # --- unconfirmed token
    rid = RbNaCl::Random.random_bytes 32
    @request.headers["HTTP_#{TOKEN}"] = b64enc rid
    head :prove_hpk, hpk: hpk
    _fail_response :precondition_failed 

    # --- with token 
    token = RbNaCl::Random.random_bytes(32)
    Rails.cache.write(rid, token ,expires_in: 0.05)
    head :prove_hpk, hpk: hpk
    _fail_response :precondition_failed # token alone not enough

    # --- missing hpk
    head :prove_hpk, hpk: ""
    _fail_response :bad_request # need hpk

    # --- short hpk
    head :prove_hpk, hpk: hpk[0..30]
    _fail_response :bad_request # need hpk

    # with a session key
    session_key = RbNaCl::PrivateKey.generate()
    Rails.cache.write("key_#{rid}", session_key ,expires_in: 0.1)
    @request.env['RAW_POST_DATA'] = "hello world"
    head :prove_hpk, { hpk: hpk}
    _fail_response :precondition_failed # no request data

    # --- missing nonce, ciphertext
    _raw_post :prove_hpk, { hpk: hpk}, RbNaCl::Random.random_bytes(32), "123"
    _fail_response :precondition_failed # not a nonce on second line

    # --- make nonce too old
    nonce1 = _client_nonce (Time.now - 35).to_i
    _raw_post :prove_hpk, { hpk: hpk}, RbNaCl::Random.random_bytes(32), nonce1, "\x0"*192
    _fail_response :precondition_failed  # expired nonce

    # Build virtual client from here

    # Node communication key - identity and first key in rachet
    client_comm_key = RbNaCl::PrivateKey.generate
    # Session temp key for current exchange with relay 
    client_sess_key = RbNaCl::PrivateKey.generate
    hpk = b64enc h2(client_comm_key.public_key)

    # create inner packet with sign proving comm_key (idenitity)
    box_inner = RbNaCl::Box.new(session_key.public_key,client_comm_key)
    nonce_inner = _client_nonce
    client_sign = xor_str h2(rid), h2(token)
    ctext = box_inner.encrypt(nonce_inner, client_sign)
    inner = Hash[ {
      nonce: nonce_inner,
      pub_key: client_comm_key.public_key.to_s,
      ctext: ctext }
      .map { |k,v| [k,b64enc(v)] }
    ]

    # create outter packet over mutual temp session keys
    box_outer = RbNaCl::Box.new(session_key.public_key,client_sess_key)
    nonce_outer = _client_nonce
    outer = box_outer.encrypt(nonce_outer,inner.to_json)
    xor_key = xor_str client_sess_key.public_key.to_s, h2(token)

    # --- corrupt ciphertext
    _raw_post :prove_hpk, { hpk: hpk }, xor_key, nonce_outer, _corrupt_str(outer)
    _fail_response :bad_request

    # --- corrupt signature
    corrupt_sign = xor_str h2(rid), h2(_corrupt_str token)
    corrupt = Hash[ {
      nonce: nonce_inner,
      pub_key: client_comm_key.public_key.to_s,
      ctext: box_inner.encrypt(nonce_inner, corrupt_sign) }
      .map { |k,v| [k,b64enc(v)] }
    ]
    _raw_post :prove_hpk, { hpk: hpk }, xor_key, nonce_outer, box_outer.encrypt(nonce_outer,corrupt.to_json)
    _fail_response :precondition_failed # signature mis-match

    # --- corrupt hpk
    _raw_post :prove_hpk, { hpk: _corrupt_str(hpk) },
      xor_key, nonce_outer, outer
    _fail_response :precondition_failed # :hpk mismatch with inner :pub_key

    # --- wrong hpk
    _raw_post :prove_hpk, { hpk: b64enc(h2(client_sess_key.public_key))},
      xor_key, nonce_outer, outer
    _fail_response :precondition_failed # :hpk mismatch with inner :pub_key

    # correct ciphertext
    _raw_post :prove_hpk, { hpk: hpk },
      xor_key, nonce_outer, outer
    _success_response
  end
end