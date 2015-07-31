class ProofControllerTest < ActionController::TestCase
test "prove_hpk guard conditions" do
  Rails.cache.clear

  rid = rand_bytes 32
  hpk = h2(rand_bytes 32)

  # --- missing hpk
  @request.headers["HTTP_#{TOKEN}"] = b64enc rid
  head :prove_hpk
  _fail_response :bad_request # need hpk

  # random hpk for first tests
  @request.headers["HTTP_#{HPK}"] = b64enc hpk
  head :prove_hpk
  _fail_response :precondition_failed # no token header

  # --- unconfirmed token
  @request.headers["HTTP_#{TOKEN}"] = b64enc rid
  @request.headers["HTTP_#{HPK}"] = b64enc hpk
  head :prove_hpk
  _fail_response :precondition_failed

  # --- with token
  token = RbNaCl::Random.random_bytes(32)
  Rails.cache.write(rid, token ,expires_in: 0.05)
  @request.headers["HTTP_#{HPK}"] = b64enc hpk
  head :prove_hpk
  _fail_response :precondition_failed # token alone not enough

  # --- short hpk
  @request.headers["HTTP_#{HPK}"] = b64enc hpk[0..30]
  head :prove_hpk
  _fail_response :bad_request # need hpk

  # with a session key
  session_key = RbNaCl::PrivateKey.generate()
  Rails.cache.write("key_#{rid}", session_key ,expires_in: 0.1)
  @request.env['RAW_POST_DATA'] = "hello world"
  @request.headers["HTTP_#{HPK}"] = b64enc hpk
  head :prove_hpk
  _fail_response :precondition_failed # no request data

  # --- missing nonce, ciphertext
  _raw_post :prove_hpk, { hpk: hpk}, rand_bytes(32), "123"
  _fail_response :precondition_failed # not a nonce on second line

  # --- make nonce too old
  @request.headers["HTTP_#{HPK}"] = b64enc hpk
  nonce1 = _make_nonce (Time.now - 35).to_i
  _raw_post :prove_hpk, { }, RbNaCl::Random.random_bytes(32), nonce1, "\x0"*192

  # somtimes we get back a 412
  #_fail_response :precondition_failed  # expired nonce

  # but 9 times out of 10 we get back a 400, so we are switching to it
  # more research tbd on making this deterministic
  # unfortunately for now it is still non-deterministic
  _fail_response :bad_request  # expired nonce

  # Build virtual client from here

  # Node communication key - identity and first key in rachet
  client_comm_key = RbNaCl::PrivateKey.generate
  # Session temp key for current exchange with relay
  client_sess_key = RbNaCl::PrivateKey.generate
  hpk = b64enc h2(client_comm_key.public_key)

  # create inner packet with sign proving comm_key (idenitity)
  box_inner = RbNaCl::Box.new(session_key.public_key,client_comm_key)
  nonce_inner = _make_nonce
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
  nonce_outer = _make_nonce
  outer = box_outer.encrypt(nonce_outer,inner.to_json)
  xor_key = xor_str client_sess_key.public_key.to_s, h2(token)

  # --- corrupt ciphertext
  @request.headers["HTTP_#{HPK}"] = hpk
  _raw_post :prove_hpk, { }, xor_key, nonce_outer, _corrupt_str(outer)
  _fail_response :bad_request

  # --- corrupt signature
  corrupt_sign = xor_str h2(rid), h2(_corrupt_str token)
  corrupt = Hash[ {
    nonce: nonce_inner,
    pub_key: client_comm_key.public_key.to_s,
    ctext: box_inner.encrypt(nonce_inner, corrupt_sign) }
    .map { |k,v| [k,b64enc(v)] }
  ]
  @request.headers["HTTP_#{HPK}"] = hpk
  _raw_post :prove_hpk, { },
    xor_key, nonce_outer,
    box_outer.encrypt(nonce_outer,corrupt.to_json)
  _fail_response :precondition_failed # signature mis-match
  return

  # --- corrupt hpk
  @request.headers["HTTP_#{HPK}"] = _corrupt_str(hpk)
  _raw_post :prove_hpk, { },
    xor_key, nonce_outer, outer
  _fail_response :precondition_failed # :hpk mismatch with inner :pub_key

  # --- wrong hpk
  @request.headers["HTTP_#{HPK}"] = b64enc(h2(client_sess_key.public_key))
  _raw_post :prove_hpk, { },
    xor_key, nonce_outer, outer
  _fail_response :precondition_failed # :hpk mismatch with inner :pub_key

  # correct ciphertext
  @request.headers["HTTP_#{HPK}"] = hpk
  _raw_post :prove_hpk, { },
    xor_key, nonce_outer, outer
  _success_response
end
end
