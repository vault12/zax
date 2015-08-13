class CommandControllerTest < ActionController::TestCase
test 'process command guards' do

  head :process_cmd
  _fail_response :precondition_failed # need hpk

  _setup_hpk
  head :process_cmd
  _fail_response :precondition_failed # need token

  _setup_token
  head :process_cmd
  _fail_response :precondition_failed

  _setup_keys
  head :process_cmd
  _fail_response :precondition_failed

  _raw_post :process_cmd, { }
  _fail_response :precondition_failed # no body

  _raw_post :process_cmd, { }, "123"
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

end

def _setup_token
  @rid = rand_bytes 32
  @request.headers["HTTP_#{TOKEN}"] = b64enc @rid
end

def _setup_hpk
  @hpk = h2(rand_bytes 32)
  @request.headers["HTTP_#{HPK}"] = b64enc @hpk
end

def _setup_keys
  @session_key = RbNaCl::PrivateKey.generate
  @client_key = RbNaCl::PrivateKey.generate

  Rails.cache.write("key_#{@rid}",@session_key)
  Rails.cache.write("inner_key_#{@hpk}",@client_key.public_key)
end

def _send_command(data)
  n = _make_nonce
  _raw_post :process_cmd, { }, n , _client_encrypt_data(n, data)
end

def _client_encrypt_data(nonce,data)
  box = RbNaCl::Box.new(@client_key.public_key, @session_key)
  box.encrypt(nonce,data.to_json)
end

def _client_decrypt_data(nonce,data)
  box = RbNaCl::Box.new(@client_key.public_key, @session_key)
  JSON.parse box.decrypt(nonce,data)
end

end
