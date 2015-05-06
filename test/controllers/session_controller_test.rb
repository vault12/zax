require 'test_helper'
require 'base64'

class SessionControllerTest < ActionController::TestCase
  public
  test "new session handshake" do
    head :new_session_token
    _fail_response :precondition_failed # missing header
    
    @request.headers["HTTP_REQUEST_TOKEN"] = RbNaCl::Random.random_bytes 32
    head :new_session_token
    _fail_response :precondition_failed # wrong encoding

    @request.headers["HTTP_REQUEST_TOKEN"] = Base64.strict_encode64 RbNaCl::Random.random_bytes 32
    head :new_session_token
    _success_response
  end

  test "verify_session_token w/o context" do
    head :verify_session_token
    _fail_response :precondition_failed # missing header

    @request.headers["HTTP_REQUEST_TOKEN"] = RbNaCl::Random.random_bytes 32
    head :verify_session_token
    _fail_response :precondition_failed # wrong encoding

    @request.headers["HTTP_REQUEST_TOKEN"] = Base64.strict_encode64 RbNaCl::Random.random_bytes 32
    head :verify_session_token
    _fail_response :precondition_failed # wrong token
  end
end