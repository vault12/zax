# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class ProveHpkTest < ActionDispatch::IntegrationTest
  test 'session, prove hpk token flow' do

    # generate a client token
    @client_token = RbNaCl::Random.random_bytes 32

    _post '/start_session', @client_token
    _success_response

    body = response.body
    lines = _check_body(body)

    # get the relay token from the response body
    @relay_token = lines[0].from_b64

    # hash the client token
    h2_client_token = h2(@client_token)

    client_relay = @client_token + @relay_token
    h2_client_relay = h2(client_relay)

    _post '/verify_session', h2_client_token, h2_client_relay
    _success_response

    body = response.body
    lines = _check_body(body)
    @session_key = lines[0].from_b64

    ### --------------------------------------------------
    ### Start set up of /prove
    ### --------------------------------------------------

    # hash both the client and relay token
    h2_client_token = h2(@client_token)
    h2_relay_token = h2(@relay_token)

    #
    # Build virtual client from here
    #

    # Node communication key - identity and first key in rachet
    client_comm_sk = RbNaCl::PrivateKey.generate

    # Session temp key for current exchange with relay
    client_temp_sk = RbNaCl::PrivateKey.generate

    # Get the public key from the private key
    client_temp_pk = client_temp_sk.public_key.to_s

    # Client creates 32 byte session signature
    # h₂(a_temp_pk,relay_token,client_token)

    session_sign1 = client_temp_pk + @relay_token
    session_sign = session_sign1 + @client_token
    hsession_sign = h2(session_sign)

    # And then check and make sure its 32 bytes
    assert_equal(32, hsession_sign.length)

    # create inner packet with sign proving comm_key (identity)

    # Client encrypts signature with
    # crypto_box(nonce2, r_sess_pk, a_comm_sk)
    # resulting in cyphertext_inner
    box_inner = RbNaCl::Box.new(@session_key, client_comm_sk)
    nonce_inner = _make_nonce

    ctext = box_inner.encrypt(nonce_inner, hsession_sign)
    inner = Hash[ {
      nonce: nonce_inner,
      pub_key: client_comm_sk.public_key.to_s,
      ctext: ctext }
      .map { |k,v| [k,v.to_b64] }
    ]

    # Client encrypts JSON object with
    # crypto_box(nonce, r_sess_pk, a_sess_sk)
    # resulting in cyphertext

    box_outer = RbNaCl::Box.new(@session_key, client_temp_sk)
    nonce_outer = _make_nonce

    outer = box_outer.encrypt(nonce_outer, inner.to_json)

    _post '/prove', h2_client_token,
                    client_temp_pk,
                    nonce_outer,
                    outer
  end

  # a wrong proof signature is a client error — 400 with the error
  # header, never a NameError-driven 500.
  test 'prove with wrong signature returns bad_request' do
    @client_token = RbNaCl::Random.random_bytes 32
    _post '/start_session', @client_token
    _success_response
    @relay_token = _check_body(response.body)[0].from_b64

    _post '/verify_session', h2(@client_token), h2(@client_token + @relay_token)
    _success_response
    @session_key = _check_body(response.body)[0].from_b64

    client_comm_sk = RbNaCl::PrivateKey.generate
    client_temp_sk = RbNaCl::PrivateKey.generate
    client_temp_pk = client_temp_sk.public_key.to_s

    # WRONG signature: random bytes instead of h2(temp_pk + relay + client tokens)
    bad_sign = rand_bytes 32

    box_inner = RbNaCl::Box.new(@session_key, client_comm_sk)
    nonce_inner = _make_nonce
    inner = Hash[{ nonce: nonce_inner,
                   pub_key: client_comm_sk.public_key.to_s,
                   ctext: box_inner.encrypt(nonce_inner, bad_sign) }.map { |k, v| [k, v.to_b64] }]

    box_outer = RbNaCl::Box.new(@session_key, client_temp_sk)
    nonce_outer = _make_nonce
    outer = box_outer.encrypt(nonce_outer, inner.to_json)

    _post '/prove', h2(@client_token), client_temp_pk, nonce_outer, outer
    _fail_response :bad_request
  end

  # a validly encrypted outer box carrying NON-JSON plaintext is a client
  # error — 400, never JSON::ParserError reaching the severe handler as a
  # 500 (and a client-triggerable Sentry event)
  test 'prove with non-JSON inner packet returns bad_request' do
    @client_token = RbNaCl::Random.random_bytes 32
    _post '/start_session', @client_token
    _success_response
    @relay_token = _check_body(response.body)[0].from_b64

    _post '/verify_session', h2(@client_token), h2(@client_token + @relay_token)
    _success_response
    @session_key = _check_body(response.body)[0].from_b64

    client_temp_sk = RbNaCl::PrivateKey.generate
    client_temp_pk = client_temp_sk.public_key.to_s

    box_outer = RbNaCl::Box.new(@session_key, client_temp_sk)
    nonce_outer = _make_nonce
    # exactly 176 plaintext bytes: with the 16-byte box MAC that is the 192
    # ciphertext bytes the l4 length check expects (256 b64 chars) — any
    # shorter plaintext is rejected on line length before JSON.parse runs
    outer = box_outer.encrypt(nonce_outer, 'x' * 176)

    _post '/prove', h2(@client_token), client_temp_pk, nonce_outer, outer
    _fail_response :bad_request
  end
end
