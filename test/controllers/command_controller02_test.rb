class CommandControllerTest < ActionController::TestCase

test 'process command 02 upload count download delete' do

  _setup_token
  _setup_hpk
  _setup_keys

  to_hpk = RbNaCl::Random.random_bytes(32)
  to_hpk = b64enc to_hpk

#---------------------------------------------------------
#      upload
#---------------------------------------------------------

  _send_command cmd: 'upload', to: to_hpk, payload: 'hw 0'
  _send_command cmd: 'upload', to: to_hpk, payload: 'hw 1'
  _send_command cmd: 'upload', to: to_hpk, payload: 'hw 2'

#---------------------------------------------------------
#        count
#---------------------------------------------------------

  results = _send_command cmd: 'count'
  _success_response

  lines = response.body.split "\n"
  assert_equal(2, lines.length)

  rn = b64dec lines[0]
  rct = b64dec lines[1]
  data = _client_decrypt_data rn,rct
  @count = data["count"]
  #assert_equal 3, @count

#---------------------------------------------------------
#        download
#---------------------------------------------------------

  _send_command cmd: 'download'
  _success_response

  lines = response.body.split "\n"
  assert_equal(2, lines.length)

  rn = b64dec lines[0]
  rct = b64dec lines[1]
  data = _client_decrypt_data rn,rct

  assert_not_nil data
  #assert_equal 3, data.length

#---------------------------------------------------------
#        delete
#---------------------------------------------------------

  data.each do |message|
    _send_command cmd: 'delete', ids: [message["nonce"]]
  end

#---------------------------------------------------------
#        count
#---------------------------------------------------------

  results = _send_command cmd: 'count'
  _success_response

  lines = response.body.split "\n"
  assert_equal(2, lines.length)

  rn = b64dec lines[0]
  rct = b64dec lines[1]
  data = _client_decrypt_data rn,rct
  @count = data["count"]
  assert_equal 0, @count

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
  _raw_post :process_cmd, { }, n , _client_encrypt_data( n, data)
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
