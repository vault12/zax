# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class ProofControllerTest < ActionController::TestCase
public

test 'prove_hpk' do

  # set the token timeout
  @tmout = Rails.configuration.x.relay.token_timeout

  # create the client token and write it to the Rails cache
  _setup_token

  # create the relay token and write it to the Rails cache
  _make_relay_token

  # hash both the client and relay token
  h2_client_token = h2(@client_token)
  h2_relay_token = h2(@relay_token)

  #
  # Build the virtual client from here
  #

  # Node communication key - identity and first key in rachet
  client_comm_sk = RbNaCl::PrivateKey.generate

  # Session temp key for current exchange with relay
  client_temp_sk = RbNaCl::PrivateKey.generate

  # Get the public key from the private key
  client_temp_pk = client_temp_sk.public_key.to_s

  # Generate a session key and write it to the rails cache
  @session_key = RbNaCl::PrivateKey.generate()
  Rails.cache.write("session_key_#{h2_client_token}", @session_key, :expires_in => @tmout)

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

  box_inner = RbNaCl::Box.new(@session_key.public_key, client_comm_sk)
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

  box_outer = RbNaCl::Box.new(@session_key.public_key, client_temp_sk)
  nonce_outer = _make_nonce

  outer = box_outer.encrypt(nonce_outer, inner.to_json)

  p1 = "#{h2_client_token.to_b64}"
  p2 = "#{client_temp_pk.to_b64}"
  p3 = "#{nonce_outer.to_b64}"
  p4 = "#{outer.to_b64}"

  assert_equal(p1.length, 44)
  assert_equal(p2.length, 44)
  assert_equal(p3.length, 32)
  assert_equal(p4.length, 256)

  plength = p1.length + p2.length + p3.length + p4.length
  assert_equal(plength,376)

  _raw_post :prove_hpk, {}, h2_client_token,
                            client_temp_pk,
                            nonce_outer, outer
  _success_response
end

def _make_relay_token
  @relay_token = RbNaCl::Random.random_bytes(32)
  h2_client_token = h2(@client_token)
  # Establish and cache relay token for timeout duration
  Rails.cache.write("relay_token_#{h2_client_token}", @relay_token, expires_in: @tmout)
  # Sanity check server-side RNG
  if not @relay_token or @relay_token.length != 32
    raise RequestIDError.new(self, @relay_token), "Missing #{TOKEN}"
  end
  return @relay_token
end

end
