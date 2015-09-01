class ProofControllerTest < ActionController::TestCase
public

test "prove_hpk" do

  @tmout = Rails.configuration.x.relay.token_timeout
  _setup_token
  _make_relay_token
  h2_client_token = h2(@client_token)
  h2_relay_token = h2(@relay_token)

  # Build virtual client from here
  # Node communication key - identity and first key in rachet
  client_comm_sk = RbNaCl::PrivateKey.generate
  # Session temp key for current exchange with relay
  client_temp_sk = RbNaCl::PrivateKey.generate
  # not sure here if it matters whether to use to_s or to_bytes
  # client_temp_pk = client_temp_sk.public_key.to_bytes
  client_temp_pk = client_temp_sk.public_key.to_s

  hpk = h2(client_comm_sk.public_key)

  #print "pct hpk = #{b64enc hpk}"; puts
  #print "pct client_temp_pk = #{b64enc client_temp_pk}"; puts

  masked_hpk = xor_str(hpk,h2_relay_token)
  masked_client_temp_pk = xor_str(client_temp_pk,h2_relay_token)

  @session_key = RbNaCl::PrivateKey.generate()
  Rails.cache.write("session_key_#{h2_client_token}", @session_key, :expires_in => @tmout)

  # Alice creates session_sign = h₂(a_temp_pk,relay_token,client_token)
  # Alice creates 32 byte session signature as h₂(a_temp_pk,relay_token,client_token)

  session_sign1 = concat_str(client_temp_pk,@relay_token)
  session_sign = concat_str(session_sign1,@client_token)
  hsession_sign = h2(session_sign)
  assert_equal(32,hsession_sign.length)

  # create inner packet with sign proving comm_key (idenitity)
  box_inner = RbNaCl::Box.new(@session_key.public_key,client_comm_sk)
  nonce_inner = _make_nonce

  ctext = box_inner.encrypt(nonce_inner, hsession_sign)

  inner = Hash[ {
    nonce: nonce_inner,
    pub_key: client_comm_sk.public_key.to_s,
    ctext: ctext }
    .map { |k,v| [k,b64enc(v)] }
  ]

  box_outer = RbNaCl::Box.new(@session_key.public_key,client_temp_sk)
  nonce_outer = _make_nonce

  outer = box_outer.encrypt(nonce_outer,inner.to_json)

  #print "pct masked_hpk = #{b64enc masked_hpk}"; puts
  #print "pct masked_client_temp_pk = #{b64enc masked_client_temp_pk}"; puts

  p1 = "#{b64enc h2_client_token}"
  p2 = "#{b64enc masked_hpk}"
  p3 = "#{b64enc masked_client_temp_pk}"
  p4 = "#{b64enc nonce_outer}"
  p5 = "#{b64enc outer}"

# print 'p1 = ', p1.length; puts
# print 'p2 = ', p2.length; puts
# print 'p3 = ', p3.length; puts
# print 'p4 = ', p4.length; puts
# print 'p5 = ', p5.length; puts

  assert_equal(p1.length,44)
  assert_equal(p2.length,44)
  assert_equal(p3.length,44)
  assert_equal(p4.length,32)
  assert_equal(p5.length,256)

  plength = p1.length + p2.length + p3.length + p4.length + p5.length
# print 'prove parameters length = ', plength; puts
  assert_equal(plength,420)

  _raw_post :prove_hpk, {}, h2_client_token,
                            masked_hpk, masked_client_temp_pk,
                            nonce_outer, outer
  _success_response
end

def _make_relay_token
  @relay_token = RbNaCl::Random.random_bytes(32)
  h2_client_token = h2(@client_token)
  # Establish and cache relay token for timeout duration
  Rails.cache.write("relay_token_#{h2_client_token}", @relay_token, expires_in: @tmout)
  #print "#{INFO} @client_token = #{b64enc @client_token}"; puts
  #print "#{INFO} @relay_token #{b64enc @relay_token}"; puts
  #print "#{INFO} h2 client_token = #{b64enc h2_client_token}"; puts
  # Sanity check server-side RNG
  if not @relay_token or @relay_token.length != 32
    raise RequestIDError.new(self,@relay_token), "Missing #{TOKEN}"
  end
  return @relay_token
end

end
