# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class VerifySessionTest < ActionDispatch::IntegrationTest
  test 'start session token flow' do

    post '/start_session', nil
    _fail_response :bad_request # wrong token

    @client_token = RbNaCl::Random.random_bytes 32
    _post '/start_session', @client_token
    _success_response

    @client_token = RbNaCl::Random.random_bytes 31
    _post '/start_session', @client_token
    _fail_response :bad_request # wrong token

    @client_token = b64enc RbNaCl::Random.random_bytes 32
    _post '/start_session', @client_token
    _fail_response :bad_request

    _post '/start_session', 'hello vault12'
    _fail_response :bad_request

    @client_token = RbNaCl::Random.random_bytes 32
    _post '/start_session', @client_token
    _success_response
    lines = _check_body response.body
    pkey = b64dec lines[0] # first line is token, second difficulty
    assert_not_empty pkey
    assert_not_empty lines[1]
  end
end
