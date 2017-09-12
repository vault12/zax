# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
class ProofControllerTest < ActionController::TestCase
public

test 'prove_hpk guard conditions' do

  # set the token timeout
  @tmout = Rails.configuration.x.relay.token_timeout

  # create the client token and write it to the Rails cache
  _setup_token

  # create the relay token and write it to the Rails cache
  _make_relay_token

  # hash both client and relay token
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

  box_outer = RbNaCl::Box.new(@session_key.public_key,client_temp_sk)
  nonce_outer = _make_nonce
  outer = box_outer.encrypt(nonce_outer,inner.to_json)

  lines = process_lines "#{b64enc client_temp_pk}",
                        "#{b64enc nonce_outer}"
  post :prove_hpk, body: lines
  _fail_response :bad_request # missing outer


  lines = process_lines "#{b64enc h2_client_token}",
                        "#{b64enc client_temp_pk}",
                        "#{b64enc nonce_outer}"
  post :prove_hpk, body: lines
  _fail_response :bad_request # missing outer


  lines = process_lines "#{b64enc h2_client_token}",
                        "#{b64enc nonce_outer}",
                        "#{b64enc outer}"
  post :prove_hpk, body: lines
  _fail_response :bad_request # missing outer


  lines = process_lines "#{b64enc h2_client_token}",
                        "#{b64enc client_temp_pk}",
                        "#{b64enc outer}"
  post :prove_hpk, body: lines
  _fail_response :bad_request # missing outer


  lines = process_lines "#{b64enc h2_client_token}",
                        "#{b64enc client_temp_pk}",
                        "#{b64enc nonce_outer}"
  post :prove_hpk, body: lines
  _fail_response :bad_request # missing outer


  lines = process_lines "#{b64enc h2_client_token}",
                        "#{b64enc client_temp_pk}",
                        "#{b64enc nonce_outer}",
                        "#{b64enc outer}"

  post :prove_hpk, body: lines
  _success_response
end

def process_lines *lines
    lines.reduce('') { |s,v| s+="#{v}\n" }
end

def _make_relay_token
  @relay_token = RbNaCl::Random.random_bytes(32)
  h2_client_token = h2(@client_token)
  # Establish and cache relay token for timeout duration
  Rails.cache.write("relay_token_#{h2_client_token}", @relay_token, expires_in: @tmout)
  # Sanity check server-side RNG
  if not @relay_token or @relay_token.length != 32
    raise RequestIDError.new(self,@relay_token), "Missing #{TOKEN}"
  end
  return @relay_token
end

end
