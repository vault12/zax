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

  print "pct hpk = #{b64enc hpk}"; puts
  print "pct client_temp_pk = #{b64enc client_temp_pk}"; puts

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

  print "pct masked_hpk = #{b64enc masked_hpk}"; puts
  print "pct masked_client_temp_pk = #{b64enc masked_client_temp_pk}"; puts

  _raw_post :prove_hpk, {}, h2_client_token,
                            masked_hpk, masked_client_temp_pk,
                            nonce_outer, outer
  return

  # create outter packet over mutual temp session keys


#-------------------------------------------------------------


  rid = rand_bytes 32
  hpk = h2(rand_bytes 32)

  # --- missing hpk
  @request.headers["HTTP_#{TOKEN}"] = b64enc rid
  @request.headers["HTTP_#{HPK}"] = b64enc hpk

  # --- with token
  token = RbNaCl::Random.random_bytes(32)
  Rails.cache.write(rid, token)

  # with a session key
  session_key = RbNaCl::PrivateKey.generate()
  Rails.cache.write("key_#{rid}", session_key)
  @request.env['RAW_POST_DATA'] = "hello world"

  # --- missing nonce, ciphertext
  _raw_post :prove_hpk, { hpk: hpk}, rand_bytes(32), "123"

  nonce1 = _make_nonce (Time.now - 35).to_i
  _raw_post :prove_hpk, { }, RbNaCl::Random.random_bytes(32), nonce1, "\x0"*192

  # Build virtual client from here

  # Node communication key - identity and first key in rachet
  client_comm_sk = RbNaCl::PrivateKey.generate
  # Session temp key for current exchange with relay
  client_sess_key = RbNaCl::PrivateKey.generate
  hpk = b64enc h2(client_comm_sk.public_key)

  # create inner packet with sign proving comm_key (idenitity)
  box_inner = RbNaCl::Box.new(session_key.public_key,client_comm_sk)
  nonce_inner = _make_nonce
  client_sign = xor_str h2(rid), h2(token)
  ctext = box_inner.encrypt(nonce_inner, client_sign)
  inner = Hash[ {
    nonce: nonce_inner,
    pub_key: client_comm_sk.public_key.to_s,
    ctext: ctext }
    .map { |k,v| [k,b64enc(v)] }
  ]

  # create outter packet over mutual temp session keys
  box_outer = RbNaCl::Box.new(session_key.public_key,client_sess_key)
  nonce_outer = _make_nonce
  outer = box_outer.encrypt(nonce_outer,inner.to_json)
  xor_key = xor_str client_sess_key.public_key.to_s, h2(token)

  # --- corrupt signature
  corrupt_sign = xor_str h2(rid), h2(_corrupt_str token)
  corrupt = Hash[ {
    nonce: nonce_inner,
    pub_key: client_comm_sk.public_key.to_s,
    ctext: box_inner.encrypt(nonce_inner, corrupt_sign) }
    .map { |k,v| [k,b64enc(v)] }
  ]

  _raw_post :prove_hpk, { },
    xor_key, nonce_outer,
    box_outer.encrypt(nonce_outer,corrupt.to_json)

  _raw_post :prove_hpk, { },
    xor_key, nonce_outer, outer
  _success_response
end

def _make_relay_token
  @relay_token = RbNaCl::Random.random_bytes(32)
  h2_client_token = h2(@client_token)
  # Establish and cache relay token for timeout duration
  Rails.cache.write("relay_token_#{h2_client_token}", @relay_token, expires_in: @tmout)
  print "#{INFO} @client_token = #{b64enc @client_token}"; puts
  print "#{INFO} @relay_token #{b64enc @relay_token}"; puts
  print "#{INFO} h2 client_token = #{b64enc h2_client_token}"; puts
  # Sanity check server-side RNG
  if not @relay_token or @relay_token.length != 32
    raise RequestIDError.new(self,@relay_token), "Missing #{TOKEN}"
  end
  return @relay_token
end

end
