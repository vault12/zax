require 'test_helper'
require "utils"

class ProofControllerTest < ActionController::TestCase
  include Utils

  test "prove_hpk guard conditions" do
    Rails.cache.clear

    head :prove_hpk
    _fail_response :precondition_failed # no header

    rid = RbNaCl::Random.random_bytes 32
    @request.headers["HTTP_REQUEST_TOKEN"] = b64enc rid
    head :prove_hpk
    _fail_response :precondition_failed # unconfirmed token

    # with token 
    token = RbNaCl::Random.random_bytes(32)
    Rails.cache.write(rid, token ,expires_in: 0.05)
    head :prove_hpk
    _fail_response :precondition_failed # token alone not enough

    # with a session key
    session_key = RbNaCl::PrivateKey.generate()
    Rails.cache.write("key_#{rid}", session_key ,expires_in: 0.1)
    @request.env['RAW_POST_DATA'] = "hello world"
    head :prove_hpk
    _fail_response :precondition_failed # no request data

    @request.env['RAW_POST_DATA'] =
    "#{b64enc RbNaCl::Random.random_bytes 32}\r\n"\
    "123\r\n"
    post :prove_hpk
    _fail_response :precondition_failed # not a nonce on second line

    # make nonce too old
    nonce1 = _client_nonce (Time.now - 35).to_i
    @request.env['RAW_POST_DATA'] =
    "#{b64enc RbNaCl::Random.random_bytes 32}\n"\
    "#{b64enc nonce1}\n"+
    "x"*192
    post :prove_hpk
    _fail_response :precondition_failed  # expired nonce

    # --- Build virtual client from here

    # Node communication key - identity and first key in rachet
    client_comm_key = RbNaCl::PrivateKey.generate
    
    # Session temp key for current exchange with relay 
    client_sess_key = RbNaCl::PrivateKey.generate

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

    # corrupt ciphertext
    corrupt = outer.clone
    corrupt[0] = [corrupt[0].ord+1].pack("C")
    @request.env['RAW_POST_DATA'] =
    "#{b64enc xor_key}\n"\
    "#{b64enc nonce_outer}\n"\
    "#{b64enc corrupt}"
    post :prove_hpk
    _fail_response :bad_request 

    # correct ciphertext
     @request.env['RAW_POST_DATA'] =
    "#{b64enc xor_key}\n"\
    "#{b64enc nonce_outer}\n"\
    "#{b64enc outer}"
    post :prove_hpk
    _success_response
  end
end