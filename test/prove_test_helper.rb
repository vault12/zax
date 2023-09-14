# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class ProveTestHelper < ActionDispatch::IntegrationTest
  include Helpers::TransactionHelper

  def setup_prove
      @client_token = RbNaCl::Random.random_bytes 32
      _post "/start_session", @client_token
      _success_response

      body = response.body
      lines = _check_body(body)
      @relay_token = lines[0].from_b64
      h2_client_token = h2(@client_token)

      client_relay = @client_token + @relay_token
      h2_client_relay = h2(client_relay)

      _post '/verify_session', h2_client_token, h2_client_relay
      _success_response

      body = response.body
      lines = _check_body(body)
      @session_key = lines[0].from_b64

      h2_client_token = h2(@client_token)
      h2_relay_token = h2(@relay_token)

      client_comm_sk = RbNaCl::PrivateKey.generate
      client_temp_sk = RbNaCl::PrivateKey.generate
      client_temp_pk = client_temp_sk.public_key.to_s

      # Alice creates session_sign = h₂(a_temp_pk, relay_token, client_token)
      # Alice creates 32 byte session signature as h₂(a_temp_pk, relay_token, client_token)

      session_sign1 = client_temp_pk + @relay_token
      session_sign = session_sign1 + @client_token
      hsession_sign = h2(session_sign)
      assert_equal(32, hsession_sign.length)

      # create inner packet with sign proving comm_key (idenitity)
      box_inner = RbNaCl::Box.new(@session_key, client_comm_sk)
      nonce_inner = _make_nonce

      ctext = box_inner.encrypt(nonce_inner, hsession_sign)

      inner = Hash[ {
        nonce: nonce_inner,
        pub_key: client_comm_sk.public_key.to_s,
        ctext: ctext }
        .map { |k,v| [k,v.to_b64] }
      ]

      box_outer = RbNaCl::Box.new(@session_key, client_temp_sk)
      nonce_outer = _make_nonce

      outer = box_outer.encrypt(nonce_outer, inner.to_json)

      _post '/prove', h2_client_token,
                      client_temp_pk,
                      nonce_outer,
                      outer
      _success_response

      return h2(client_comm_sk.public_key) # return hpk
  end
end
