class SessionControllerTest < ActionController::TestCase
public

test "new session token" do
  _raw_post :start_session_token, { }
  _fail_response :internal_server_error # no response body

  client_token = RbNaCl::Random.random_bytes(24)
  _raw_post :start_session_token, { }, client_token
  _fail_response :internal_server_error # 24 instead of 32 bytes

  _setup_token
  _raw_post :start_session_token, { }, @client_token
  _success_response
end

test "verify session token" do
  _setup_token
  _raw_post :start_session_token, { }, @client_token
  _success_response
  body = response.body
  lines = _check_body(body)

  ### debug
  pclient_token = b64enc @client_token
  print 'client token = ', pclient_token; puts
  print 'relay token = ', lines[0]; puts
  ### end debug

  @relay_token = b64dec lines[0]
  h2_client_token = h2(@client_token)

  ### debug
  ph2_client_token = b64enc h2_client_token
  print 'h2 client token = ', ph2_client_token; puts
  ### end debug

  client_relay = concat_str(@client_token,@relay_token)
  h2_client_relay = h2(client_relay)

  ### debug
  ph2_client_relay = b64enc h2_client_relay
  print 'h2 client relay = ', ph2_client_relay; puts
  ### end debug

  _raw_post :verify_session_token, {}, h2_client_token, h2_client_relay
  _success_response
  body = response.body
  lines = _check_body(body)
  ### debug
  print 'session key xor client token = ', lines[0]; puts
  ### end debug
  skxorct = b64dec lines[0]
  session_key = xor_str(skxorct,@client_token)
  print 'session key = ', "#{b64enc session_key}"; puts

end

end

=begin
test "verify_session_token guards" do
  head :verify_session_token
  _fail_response :precondition_failed # missing header

  @request.headers["HTTP_#{TOKEN}"] = rand_bytes 32
  head :verify_session_token
  _fail_response :precondition_failed # wrong encoding

  @request.headers["HTTP_#{TOKEN}"] = b64enc rand_bytes 32
  head :verify_session_token
  _fail_response :precondition_failed # wrong token
end

test "token is consitent until timeout" do
  token = b64enc rand_bytes 32
  @request.headers["HTTP_#{TOKEN}"] = token
  get :new_session_token
  _success_response
  counter_token = Base64.decode64(response.body)

  @request.headers["HTTP_#{TOKEN}"] = token
  get :new_session_token
  _success_response
  assert_equal(Base64.decode64(response.body), counter_token)
  #
  # Comment out temporarily so that tests run faster
  #

  ...THIS ALL GETS COMMENTED OUT BELOW HERE...

  sleep Rails.configuration.x.relay.token_timeout
  @request.headers["HTTP_#{TOKEN}"] = token
  post :verify_session_token
  logger.info "h:"+@response.headers["X-Error-Details"]
  _fail_response :precondition_failed # timed out
=end
