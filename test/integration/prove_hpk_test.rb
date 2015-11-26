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
    @relay_token = b64dec lines[0]

    # hash the client token
    h2_client_token = h2(@client_token)

    client_relay = @client_token + @relay_token
    h2_client_relay = h2(client_relay)

    _post '/verify_session', h2_client_token, h2_client_relay
    _success_response

    body = response.body
    lines = _check_body(body)
    @session_key = b64dec lines[0]

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
      .map { |k,v| [k,b64enc(v)] }
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
end
