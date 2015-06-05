require 'test_helper'

class SessionControllerTest < ActionController::TestCase
  public
  test "new session handshake" do
    head :new_session_token
    _fail_response :precondition_failed # missing header
    
    @request.headers["HTTP_#{TOKEN}"] = rand_bytes 32
    head :new_session_token
    _fail_response :precondition_failed # wrong encoding

    @request.headers["HTTP_#{TOKEN}"] = b64enc rand_bytes 32
    head :new_session_token
    _success_response
  end

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

    sleep Rails.configuration.x.relay.token_timeout
    @request.headers["HTTP_#{TOKEN}"] = token
    post :verify_session_token
    logger.info "h:"+@response.headers["X-Error-Details"]
    _fail_response :precondition_failed # timed out
  end
end