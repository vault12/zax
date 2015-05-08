require 'test_helper'
require 'response_helper'

class ProofControllerTest < ActionController::TestCase
  include ResponseHelper

  test "prove :hpk guard" do
    head :prove_hpk
    _fail_response :precondition_failed # no header

    rid = RbNaCl::Random.random_bytes 32
    @request.headers["HTTP_REQUEST_TOKEN"] = Base64.strict_encode64 rid
    head :prove_hpk
    _fail_response :precondition_failed # unconfirmed token

    # with token 
    Rails.cache.write(rid, token = RbNaCl::Random.random_bytes(32),
      expires_in: 0.05)
    head :prove_hpk
    _fail_response :precondition_failed # token alone not enough

    # with session key
    Rails.cache.write("key_#{rid}", sessio_key = RbNaCl::PrivateKey.generate(),
      expires_in: 0.05)
    @request.env['RAW_POST_DATA'] = "hello world"
    head :prove_hpk
    _fail_response :precondition_failed # no request data

    @request.env['RAW_POST_DATA'] =
    "#{Base64.strict_encode64 RbNaCl::Random.random_bytes 32}\n"\
    "123"
    head :prove_hpk
    _fail_response :precondition_failed # not a nonce on second line

    # expired nonce
    nonce1 = _client_nonce (Time.now - 35).to_i
    @request.env['RAW_POST_DATA'] =
    "#{Base64.strict_encode64 RbNaCl::Random.random_bytes 32}\n"\
    "#{Base64.strict_encode64 nonce1}"
    head :prove_hpk
    _fail_response :precondition_failed

    # Build virtual client from here
    client_sign = xor_str h2(rid), h2(token)
    client_sess_key = RbNaCl::PrivateKey.generate
    client_comm_key = RbNaCl::PrivateKey.generate
    box = RbNaCl::Box.new(sessio_key.public_key,client_sess_key)

    nonce_inner = _client_nonce
    ctext = box.encrypt(nonce_inner, client_sign)

    inner = { nonce: nonce_inner, pub_key: client_sess_key.public_key.to_s,
      ctext: ctext }
    inner = inner.each_value { |v| Base64.strict_encode64 v }
    logger.info inner

  end
end