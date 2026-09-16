# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class VerifySessIntegrationTest < ActionDispatch::IntegrationTest
  test 'verify session token flow' do
    @client_token = rand_bytes 32
    _post '/start_session', @client_token
    _success_response

    body = response.body
    lines = _check_body(body)
    @relay_token = lines[0].from_b64
    h2_client_token = h2(@client_token)

    # wrong token
    _post '/verify_session', rand_bytes(32), rand_bytes(32)
    _fail_response :unauthorized

    # handshake mismatch
    _post '/verify_session', h2_client_token, 'hiii' * 8
    _fail_response :unauthorized

     # handshake mismatch 2
    _post '/verify_session', h2_client_token, h2_client_token
    _fail_response :unauthorized

    h2_client_relay = h2(@client_token + @relay_token)

    _post '/verify_session', h2_client_token, h2_client_relay
    _success_response

    body = response.body
    lines = _check_body(body)
  end

  # a verified handshake is single-use — replaying the same verify
  # body (same solved PoW) must be rejected, not re-mint the session key.
  test 'verify session is single use' do
    @client_token = rand_bytes 32
    _post '/start_session', @client_token
    _success_response
    @relay_token = _check_body(response.body)[0].from_b64

    h2_client_token = h2(@client_token)
    _post '/verify_session', h2_client_token, h2(@client_token + @relay_token)
    _success_response
    first_key = _check_body(response.body)[0].from_b64

    # Identical replay: rejected, and the minted session key is untouched
    _post '/verify_session', h2_client_token, h2(@client_token + @relay_token)
    _fail_response :unauthorized
    assert_equal first_key,
      Rails.cache.read("session_key_#{h2_client_token}").public_key.to_bytes,
      'replay must not overwrite the minted session key'

    # Restarting the handshake — same client token, fresh relay token and
    # therefore a fresh PoW — reopens the single-use verify slot
    _post '/start_session', @client_token
    _success_response
    relay2 = _check_body(response.body)[0].from_b64

    _post '/verify_session', h2_client_token, h2(@client_token + relay2)
    _success_response
    second_key = _check_body(response.body)[0].from_b64
    assert_not_equal first_key, second_key, 'new handshake mints a new session key'
  end

  # a failed session-key generation is a grave relay fault — the client must
  # receive :internal_server_error (the documented signal to avoid this relay),
  # NOT :bad_request. `performed?` guard silently downgraded it to
  # 400 because ServerKeyError (unlike ServerRandomError) didn't set the code
  # before super. This asserts the 500 by forcing key generation to fail.
  test 'session key generation failure returns 500, not 400' do
    require 'minitest/mock'
    @client_token = rand_bytes 32
    _post '/start_session', @client_token
    _success_response
    @relay_token = _check_body(response.body)[0].from_b64
    h2_client_token = h2(@client_token)

    # Force generation to return nil at the exact ServerKeyError raise site.
    RbNaCl::PrivateKey.stub(:generate, nil) do
      _post '/verify_session', h2_client_token, h2(@client_token + @relay_token)
    end
    _fail_response :internal_server_error
  end

  # a relay-wide ceiling on the crypto-heavy handshake path sheds excess load with 503.
  # Global (one Redis counter), so it holds across all Puma workers.
  # TTL-race regression: a global counter resurrected without a TTL (window
  # expired between SET NX and INCR) would 503 the handshake path forever.
  # The limiter must re-arm the TTL so the window still closes.
  test 'global handshake ceiling re-arms a counter that lost its TTL' do
    save = Rails.configuration.x.relay.max_global_requests_per_seconds
    Rails.configuration.x.relay.max_global_requests_per_seconds = [3, 60]
    $redis.set 'rate_global_handshake', 100 # over budget with NO TTL
    begin
      _post '/start_session', rand_bytes(32)
      _fail_response :service_unavailable # still enforced while poisoned...
      assert_operator $redis.ttl('rate_global_handshake'), :>, 0,
        'limiter must re-arm the TTL so the ceiling cannot become permanent'
    ensure
      Rails.configuration.x.relay.max_global_requests_per_seconds = save
      $redis.del 'rate_global_handshake'
    end
  end

  test 'global handshake ceiling sheds excess requests with 503' do
    save = Rails.configuration.x.relay.max_global_requests_per_seconds
    Rails.configuration.x.relay.max_global_requests_per_seconds = [3, 60]
    $redis.del 'rate_global_handshake'
    begin
      # Budget of 3 is served...
      3.times do
        _post '/start_session', rand_bytes(32)
        _success_response
      end
      # ...the 4th request is over the global ceiling: 503, not a handshake.
      _post '/start_session', rand_bytes(32)
      _fail_response :service_unavailable
    ensure
      Rails.configuration.x.relay.max_global_requests_per_seconds = save
      $redis.del 'rate_global_handshake'
    end
  end
end
