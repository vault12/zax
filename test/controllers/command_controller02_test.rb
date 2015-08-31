class CommandControllerTest < ActionController::TestCase

test 'process command 02 upload count download delete' do

  hpk = h2(rand_bytes 32)
  assert_equal(hpk.length,32)
  _setup_keys hpk

  to_hpk = RbNaCl::Random.random_bytes(32)
  to_hpk = b64enc to_hpk

#---------------------------------------------------------
#      upload
#---------------------------------------------------------

  _send_command hpk, cmd: 'upload', to: to_hpk, payload: 'hw 0'
  _send_command hpk, cmd: 'upload', to: to_hpk, payload: 'hw 1'
  _send_command hpk, cmd: 'upload', to: to_hpk, payload: 'hw 2'

#---------------------------------------------------------
#        count
#---------------------------------------------------------

  results = _send_command hpk, cmd: 'count'
  _success_response

  lines = response.body.split "\n"
  assert_equal(2, lines.length)

  rn = b64dec lines[0]
  rct = b64dec lines[1]
  data = _client_decrypt_data rn,rct

  assert_not_nil data
  assert_includes data, "count"
  assert_equal 0, data['count']
  #puts data

#---------------------------------------------------------
#        download
#---------------------------------------------------------

  _send_command hpk, cmd: 'download'
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
    _send_command hpk, cmd: 'delete', ids: [message["nonce"]]
  end

#---------------------------------------------------------
#        count
#---------------------------------------------------------

  results = _send_command hpk, cmd: 'count'
  _success_response

  lines = response.body.split "\n"
  assert_equal(2, lines.length)

  rn = b64dec lines[0]
  rct = b64dec lines[1]
  data = _client_decrypt_data rn,rct
  @count = data["count"]
  assert_equal 0, @count

end
end
