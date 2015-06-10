class CommandControllerTest < ActionController::TestCase
test 'process command guards' do
  Rails.cache.clear

  head :process_cmd
  _fail_response :bad_request # need hpk

  hpk = h2(rand_bytes 32)
  @request.headers["HTTP_#{HPK}"] = b64enc hpk
  head :process_cmd
  _fail_response :precondition_failed # no session keys

  # --- create keys ---
  session_key = RbNaCl::PrivateKey.generate
  client_master = RbNaCl::PrivateKey.generate
  client_key  = client_master.public_key
  Rails.cache.write("session_key_#{hpk}",session_key)

  head :process_cmd
  _fail_response :precondition_failed # no client keys

  Rails.cache.write("client_key_#{hpk}",client_key)

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
end

test 'process command' do
  Rails.cache.clear

  hpk = h2(rand_bytes 32)
  @request.headers["HTTP_#{HPK}"] = b64enc hpk
  
  # --- create keys ---
  @session_key = RbNaCl::PrivateKey.generate
  @client_master = RbNaCl::PrivateKey.generate
  client_key  = @client_master.public_key
  Rails.cache.write("session_key_#{hpk}",@session_key)
  Rails.cache.write("client_key_#{hpk}",client_key)

  n = _make_nonce
  _raw_post :process_cmd, { }, n , _encrypt_data( n, { cmd: 'count' })
  _success_response #:bad_request # bad ciphertext 
end

def _encrypt_data(nonce,data)
  box = RbNaCl::Box.new(@session_key.public_key, @client_master)
  box.encrypt(nonce,data.to_json)
end

end