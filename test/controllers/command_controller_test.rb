class CommandControllerTest < ActionController::TestCase
test 'process command guards' do

  hpk = h2(rand_bytes 32)
  assert_equal(hpk.length,32)
  _setup_keys hpk

  _send_command hpk, {}
  _fail_response :precondition_failed # no body
=begin
  _send_command hpk, {}, "123"
  _fail_response :precondition_failed # short body

  bad_nonce = rand_bytes 24
  _raw_post :process_cmd, { }, bad_nonce
  _fail_response :precondition_failed # short body

  _raw_post :process_cmd, { }, bad_nonce, "123"
  _fail_response :precondition_failed # failed nonce check

   _raw_post :process_cmd, { }, _make_nonce((Time.now-2.minutes).to_i), "123"
  _fail_response :precondition_failed # nonce too old

   _raw_post :process_cmd, { }, _make_nonce, "123"
  _fail_response :bad_request # bad ciphertext

  n = _make_nonce
  _raw_post :process_cmd, { }, n , _corrupt_str(_client_encrypt_data( n, { cmd: 'count' }))
  _fail_response :bad_request # corrupt ciphertext
=end
end

end
