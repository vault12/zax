require 'test_helper'

class CommandTest < ActionDispatch::IntegrationTest
  test "session, prove hpk, command token flow" do
    @client_token = RbNaCl::Random.random_bytes 32
    _post "/start_session", @client_token
    _success_response

    body = response.body
    lines = _check_body(body)
    @relay_token = b64dec lines[0]
    h2_client_token = h2(@client_token)

    ### debug
    #ph2_client_token = b64enc h2_client_token
    #print 'h2 client token = ', ph2_client_token; puts
    ### end debug

    client_relay = concat_str(@client_token,@relay_token)
    h2_client_relay = h2(client_relay)

    ### debug
    #ph2_client_relay = b64enc h2_client_relay
    #print 'h2 client relay = ', ph2_client_relay; puts
    ### end debug

    _post "/verify_session", h2_client_token, h2_client_relay
    _success_response

    body = response.body
    lines = _check_body(body)
    skxorct = b64dec lines[0]
    @session_key = xor_str(skxorct,@client_token)
    ### debug
    #print 'session key = ', "#{b64enc @session_key}"; puts
    #print 'session key xor client token = ', lines[0]; puts
    ### end debug

    ### --------------------------------------------------
    ### Start set up of /prove
    ### --------------------------------------------------

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

    # Alice creates session_sign = h₂(a_temp_pk,relay_token,client_token)
    # Alice creates 32 byte session signature as h₂(a_temp_pk,relay_token,client_token)

    session_sign1 = concat_str(client_temp_pk,@relay_token)
    session_sign = concat_str(session_sign1,@client_token)
    hsession_sign = h2(session_sign)
    assert_equal(32,hsession_sign.length)

    # create inner packet with sign proving comm_key (idenitity)
    box_inner = RbNaCl::Box.new(@session_key,client_comm_sk)
    nonce_inner = _make_nonce

    ctext = box_inner.encrypt(nonce_inner, hsession_sign)

    inner = Hash[ {
      nonce: nonce_inner,
      pub_key: client_comm_sk.public_key.to_s,
      ctext: ctext }
      .map { |k,v| [k,b64enc(v)] }
    ]

    box_outer = RbNaCl::Box.new(@session_key,client_temp_sk)
    nonce_outer = _make_nonce

    outer = box_outer.encrypt(nonce_outer,inner.to_json)

    #print "pct masked_hpk = #{b64enc masked_hpk}"; puts
    #print "pct masked_client_temp_pk = #{b64enc masked_client_temp_pk}"; puts

    _post "/prove", h2_client_token,
                    masked_hpk,
                    masked_client_temp_pk,
                    nonce_outer,
                    outer
    _success_response

    _setup_keys hpk
    to_hpk = RbNaCl::Random.random_bytes(32)
    to_hpk = b64enc to_hpk
    data = {cmd: 'upload', to: to_hpk, payload: 'hello world 0'}
    n = _make_nonce
    _post "/command", hpk, n, _client_encrypt_data(n,data)
  end
end
