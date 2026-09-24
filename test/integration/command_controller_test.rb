# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class CommandControllerTest < ActionDispatch::IntegrationTest

  test 'process basic commands' do
    ### Use hpk to upload, check and delete message
    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk

    to_key = RbNaCl::PrivateKey.generate
    to_hpk = h2(to_key.public_key)

    ### Upload
    msg_nonce = rand_bytes(24).to_b64
    msg_data = {
      cmd: 'upload',
      to: to_hpk.to_b64,
      payload: {
        ctext: 'hello world 0',
        nonce: msg_nonce
      }
    }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    msg_token = b64dec _success_response # 32 byte storage token for the message
    assert_equal(32, msg_token.length)

    ### Count

    data = {cmd: 'count'}
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response

    lines = _check_response(response.body)
    assert_equal(2, lines.length)

    rn = lines[0].from_b64
    rct = lines[1].from_b64
    data = _client_decrypt_data rn, rct

    assert_not_nil data
    assert_equal 0, data

    ### Download

    data = {cmd: 'download'}
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response

    lines = _check_response(response.body)
    assert_equal(2, lines.length)

    rn = lines[0].from_b64
    rct = lines[1].from_b64
    data = _client_decrypt_data rn, rct

    assert_not_nil data
    assert_equal data.length, 0

    ### Message status

    data = { cmd: 'messageStatus', token: msg_token.to_b64 }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    r = _success_response
    assert_operator r.to_i, :>, 0

    ### Delete
    _setup_keys to_hpk  # Now a session for dest mailbox
    data = { cmd: 'delete', payload: [msg_nonce]}
    n = _make_nonce
    _post '/command', to_hpk, n, _client_encrypt_data(n, data)
    _success_response

    ### Message is now deleted
    _setup_keys hpk
    data = { cmd: 'messageStatus', token: msg_token.to_b64 }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    r = _success_response
    assert_equal r,'-2'  # -2 is redis missing key

    ### Misc commands: entropy — fixed ENTROPY_SIZE payload;
    ### a legacy :size request field is accepted but ignored
    data = { cmd: 'getEntropy', size: 1000 }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    data = JSON.parse _success_response.from_b64, symbolize_names:true
    assert_not_nil data
    assert_not_nil data[:entropy]
    assert_equal ENTROPY_SIZE, data[:entropy].from_b64.length

    data = { cmd: 'getEntropy' }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    data = JSON.parse _success_response.from_b64, symbolize_names:true
    assert_equal ENTROPY_SIZE, data[:entropy].from_b64.length
  end

  test 'process command guards' do
    hpk = h2(rand_bytes 32)
    assert_equal(hpk.length,32)
    _setup_keys hpk

    _post '/command', hpk
    _fail_response :bad_request # no body

    _post '/command', hpk, '123'
    _fail_response :bad_request # short body

    bad_nonce = rand_bytes 24
    _post '/command', hpk, bad_nonce
    _fail_response :bad_request # short body

    bad_nonce = rand_bytes 24
    _post '/command', hpk, bad_nonce, '123'
    _fail_response :bad_request # short body

    old_nonce = _make_nonce((Time.now - 2.minutes).to_i)
    _post '/command', hpk, old_nonce
    _fail_response :bad_request # expired nonce

    _post '/command', hpk, _make_nonce, '456'
    _fail_response :bad_request # bad text

    corrupt = _corrupt_str(_client_encrypt_data( _make_nonce, {cmd: 'count'}))
    _post '/command', hpk, _make_nonce, corrupt
    _fail_response :bad_request # corrupt ciphertext
  end

  # a decryption failure must NOT dump the raw (up to 1 MB)
  # attacker-controlled request body to the log — only a bounded, hex-safe
  # summary (byte length + short hex prefix). Prevents a disk-fill amplifier
  # and log injection via raw body bytes.
  test 'decryption failure logs a bounded hex-safe body summary' do
    hpk = h2(rand_bytes 32)
    _setup_keys hpk

    # A sizeable payload so the posted body is long enough that a slice past
    # the logged prefix definitely exists.
    ctext = _client_encrypt_data(_make_nonce, { cmd: 'count', pad: 'x' * 4000 })
    corrupt = _corrupt_str(ctext, false) # break the authenticator => NaCl error
    posted_body = corrupt.to_b64         # how _encode_lines serializes the line

    log_io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log_io)
    begin
      _post '/command', hpk, _make_nonce, corrupt
      _fail_response :bad_request
    ensure
      Rails.logger = original
    end

    log = log_io.string
    # The bounded format is emitted...
    assert_match(/Decryption error for packet/, log)
    assert_match(/body \d+B prefix=\h+/, log)

    # ...the hex prefix is capped at LOG_BODY_PREFIX bytes (=> 2 hex chars each)
    prefix = log[/prefix=(\h+)/, 1]
    assert_operator prefix.length, :<=, LOG_BODY_PREFIX * 2

    # ...and the raw body was NOT dumped in full: a slice past the prefix is absent
    tail = posted_body[200, 40]
    assert tail && tail.length == 40, 'test body should be long enough to slice'
    assert_no_match(/#{Regexp.escape tail}/, log, 'raw request body must not be logged')
  end

  # a missing session must NOT be distinguishable from a present
  # session whose ciphertext failed to authenticate. Both return the same
  # :bad_request + identical X-Error-Details, so an unauthenticated caller
  # cannot use /command as a per-hpk session-presence oracle.
  test 'missing session keys are indistinguishable from a bad-ciphertext request' do
    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk

    to_key = RbNaCl::PrivateKey.generate
    to_hpk = h2(to_key.public_key)

    ### Upload works while the session is live
    msg_nonce = rand_bytes(24).to_b64
    msg_data = {
      cmd: 'upload',
      to: to_hpk.to_b64,
      payload: {
        ctext: 'hello world session presence test',
        nonce: msg_nonce
      }
    }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    msg_token = b64dec _success_response # 32 byte storage token for the message
    assert_equal(32, msg_token.length) # Works as expected

    ### Case A: session PRESENT, ciphertext does not authenticate (attacker
    ### without the session keys). Encrypt a well-formed body first, then
    ### corrupt the ctext so decrypt_data raises a NaCl auth error.
    n = _make_nonce
    good = _client_encrypt_data(n, msg_data)
    bad_ctext = _corrupt_str(good, false)
    _post '/command', hpk, n, bad_ctext
    _fail_response :bad_request
    present_details = response.headers['X-Error-Details']

    ### Case B: session ABSENT (redis restart lost all keys). Same well-formed
    ### request now can't find session keys.
    _delete_keys hpk
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    _fail_response :bad_request # was :unauthorized before the oracle fix
    absent_details = response.headers['X-Error-Details']

    ### The two responses must be identical — no presence signal leaks
    assert_equal present_details, absent_details
  end

  # a malformed HPK is an ordinary client error — 400 with error
  # header, never a NameError-driven 500 telling clients the relay is broken.
  test 'malformed hpk returns bad_request not server error' do
    n = _make_nonce
    # 33 raw bytes encode to a valid 44-char b64 line that fails the
    # 32-byte HPK length check inside _get_hpk
    _post '/command', rand_bytes(33), n
    _fail_response :bad_request
  end

  # a delete with a malformed id mixed in must succeed (200) and
  # delete the valid messages — not 400 the whole batch.
  test 'delete batch with a malformed id still succeeds' do
    hpk = h2(rand_bytes 32)
    _setup_keys hpk
    from = h2(rand_bytes 32)
    mbx = Mailbox.new hpk.to_b64
    n1, n2 = rand_bytes(24), rand_bytes(24)
    mbx.store from, n1, 'a'
    mbx.store from, n2, 'b'

    data = { cmd: 'delete', payload: [n1.to_b64, 'not strict b64 !!', n2.to_b64] }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response # 200, not a 400 that drops the batch
    assert_equal 0, mbx.count

    rds.del mbx.hpk_tag
    rds.del "msg_idx_from_#{from.to_b64}"
  end

  # Page size must be honored.
  test 'download honors requested count' do
    hpk = h2(rand_bytes 32)
    _setup_keys hpk
    from = h2(rand_bytes 32)
    mbx = Mailbox.new hpk.to_b64
    ns = Array.new(5) { rand_bytes(24) }
    ns.each_with_index { |nn, i| mbx.store from, nn, "m#{i}" }

    fetch = lambda do |params|
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, { cmd: 'download' }.merge(params))
      decrypt_2_lines _check_response _success_response
    end

    assert_equal 2, fetch.call({ count: 2 }).length, 'requested page size honored'
    assert_equal 5, fetch.call({}).length, 'default: whole mailbox'
    assert_equal 3, fetch.call({ count: 99, start: 2 }).length, 'capped by what is available'

    # expired entries inside the window must not shrink the page: simulate
    # expiry of the first two messages; a page of 2 still fills with live ones
    ns[0, 2].each { |nn| rds.del mbx.msg_tag(nn.to_b64) }
    assert_equal 2, fetch.call({ count: 2 }).length, 'page fills past expired entries'
    assert_equal 3, fetch.call({}).length, 'default read skips expired'
    assert_equal 3, fetch.call({ count: 99 }).length, 'over-ask returns all live'

    rds.del mbx.hpk_tag
    rds.keys("msg_#{mbx.hpk}_*").each { |k| rds.del k }
    rds.del "msg_idx_from_#{from.to_b64}"
  end

  # wrong-TYPED fields (types are attacker-controlled after
  # JSON.parse) must return 400, never a NoMethodError/TypeError 500.
  test 'wrong-typed command fields return bad_request not server error' do
    hpk = h2(rand_bytes 32)
    _setup_keys hpk
    to_b64 = h2(rand_bytes 32).to_b64

    [
      { cmd: 'upload', to: 12345, payload: 'hi' },              # numeric :to
      { cmd: 'upload', to: to_b64, payload: { nonce: 'x' } },   # payload hash without ctext
      { cmd: 'upload', to: to_b64, payload: { ctext: 42 } },    # non-String ctext
      { cmd: 'upload', to: to_b64, payload: ['a'] },            # array payload
      { cmd: 'upload', to: to_b64, payload: { ctext: 'c', nonce: 7 } }, # numeric nonce
      { cmd: 'download', start: 1.5 },                          # Float start
      { cmd: 'download', count: 'many' },                       # String count
      { cmd: 'download', count: -1 },                           # negative count
      { cmd: 'delete', payload: 'not-an-array' },               # String payload
      { cmd: 'delete', payload: [1, 2] },                       # non-String ids
      { cmd: 'messageStatus', token: 123 },                     # numeric token
      { cmd: 'fileStatus', uploadID: 9 },                       # numeric uploadID
      { cmd: 'downloadFileChunk', uploadID: [], part: 0 },      # array uploadID
      { cmd: 'deleteFile', uploadID: {} },                      # hash uploadID
      { cmd: 'startFileUpload', to: 5, file_size: 100,
        metadata: { ctext: 'x', nonce: rand_bytes(24).to_b64 } },       # numeric :to
      { cmd: 'startFileUpload', to: to_b64, file_size: 100,
        metadata: 'meta' },                                             # scalar metadata
      { cmd: 'startFileUpload', to: to_b64, file_size: 100,
        metadata: { ctext: 'x', nonce: 12345678 } },                    # numeric metadata nonce
    ].each do |bad|
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, bad)
      _fail_response :bad_request
    end

    # uploadFileChunk with a numeric uploadID (ctext supplied via extra line)
    n = _make_nonce
    bad = { cmd: 'uploadFileChunk', uploadID: 7, part: 0, nonce: _make_nonce.to_b64 }
    _post '/command', hpk, n, _client_encrypt_data(n, bad), rand_bytes(16)
    _fail_response :bad_request


    # an unknown command whose NAME carries CR/LF and ANSI escapes: still a
    # clean 400, and the name reaches the log only log_safe-escaped
    n = _make_nonce
    bad = { cmd: "upload\r\nFORGED relay log line \e[31malert\e[0m" }
    _post '/command', hpk, n, _client_encrypt_data(n, bad)
    _fail_response :bad_request

    # the top-level TYPE itself: an authenticated box carrying a JSON array
    # or scalar instead of an object must be a 400, never data[:cmd] raising
    # TypeError/NoMethodError into a 500 (and a Sentry event)
    [ ['upload'], 'upload', 42, nil, true ].each do |bad_top|
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, bad_top)
      _fail_response :bad_request
    end

    # a validly encrypted box whose plaintext is not JSON at all: same
    # contract — 400, never JSON::ParserError becoming a 500/Sentry event
    n = _make_nonce
    raw_box = RbNaCl::Box.new(@client_key, @session_key)
    _post '/command', hpk, n, raw_box.encrypt(n, 'definitely not json')
    _fail_response :bad_request
  end

  # Over HTTP: re-uploading with the same payload nonce must return
  # 400 (message id collision), not silently overwrite the queued message.
  test 'upload with a reused payload nonce is rejected' do
    hpk = h2(rand_bytes 32)
    _setup_keys hpk
    to_hpk = h2(rand_bytes 32)

    msg_data = {
      cmd: 'upload', to: to_hpk.to_b64,
      payload: { ctext: 'first message', nonce: rand_bytes(24).to_b64 }
    }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    _success_response

    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data) # same payload nonce
    _fail_response :bad_request
  end

  # an unauthenticated /command must NOT write to the nonce cache.
  # The replay-nonce write is deferred until after decrypt, so a request from an
  # hpk with no session dies at load_keys having grown nothing — closing the
  # pre-auth memory-exhaustion vector.
  test 'unauthenticated command does not grow the nonce cache' do
    hpk = h2(rand_bytes 32)          # valid hpk shape, but NO session in cache
    _delete_keys hpk
    n = _make_nonce
    nonce_key = "nonce_#{n.to_b64}"
    Rails.cache.delete nonce_key     # clean slate

    # Well-formed preamble, junk ciphertext: fails at load_keys (no session)...
    _post '/command', hpk, n, rand_bytes(80)
    _fail_response :bad_request
    # ...and the nonce was never recorded (pre-fix, _check_nonce wrote it up front).
    assert_nil Rails.cache.read(nonce_key),
      'unauthenticated request must not write a nonce_* key'
  end

  # Regression: deferring the nonce write must NOT weaken replay
  # protection — an exact replay of an authenticated command is still rejected.
  test 'transport-nonce replay of an authenticated command is rejected' do
    hpk = h2(rand_bytes 32)
    _setup_keys hpk
    n  = _make_nonce
    ct = _client_encrypt_data(n, { cmd: 'count' })

    _post '/command', hpk, n, ct
    _success_response
    assert_not_nil Rails.cache.read("nonce_#{n.to_b64}"),
      'authenticated command records its transport nonce'

    _post '/command', hpk, n, ct     # exact replay, same transport nonce
    _fail_response :bad_request       # nonce reuse => NonceError
  end

  # fixed-window per-hpk rate limit — the security property. Fast:
  # budget served, instant 429 once exhausted, other senders unaffected.
  test 'per-hpk rate limit rejects over-budget commands' do
    save = Rails.configuration.x.relay.max_requests_per_seconds
    Rails.configuration.x.relay.max_requests_per_seconds = [3, 60]

    hpk = h2(rand_bytes 32)
    _setup_keys hpk

    # Budget of 3 is served...
    3.times { _send_count hpk; _success_response }

    # ...then instant 429 for the rest of the window
    _send_count hpk
    _fail_response :too_many_requests
    _send_count hpk
    _fail_response :too_many_requests

    # Another sender is not affected by this hpk's exhausted budget
    hpk2 = h2(rand_bytes 32)
    _setup_keys hpk2
    _send_count hpk2
    _success_response
  ensure
    Rails.configuration.x.relay.max_requests_per_seconds = save
  end

  # Retry-After on 429: names the seconds until the fixed window reopens so
  # the client can wait it out instead of retrying blind.
  test 'per-hpk rate limit 429 carries Retry-After for the window tail' do
    save = Rails.configuration.x.relay.max_requests_per_seconds
    Rails.configuration.x.relay.max_requests_per_seconds = [1, 60]

    hpk = h2(rand_bytes 32)
    _setup_keys hpk

    _send_count hpk
    _success_response
    assert_nil response.headers['Retry-After'],
      'within-budget responses must not advertise a retry delay'

    # pin the window tail so the header provably derives from the key's TTL —
    # a constant full-window answer would pass a fresh-window assertion
    $redis.expire "rate_#{hpk.to_b64}", 7

    _send_count hpk
    _fail_response :too_many_requests
    assert_equal '8', response.headers['Retry-After'],
      'Retry-After must be the remaining window TTL rounded up by one second'
    assert_includes response.headers['Access-Control-Expose-Headers'].to_s.split(','),
      'Retry-After', 'browser clients must be allowed to read Retry-After'
  ensure
    Rails.configuration.x.relay.max_requests_per_seconds = save
  end

  # window lifecycle — a fresh budget opens once the window expires.
  # Needs a real wall-clock wait, so it lives in the SLOW group.
  test 'per-hpk rate limit opens a fresh budget after the window' do
    skip 'slow lifecycle test: set SLOW=1 to run' unless ENV['SLOW']

    save = Rails.configuration.x.relay.max_requests_per_seconds
    Rails.configuration.x.relay.max_requests_per_seconds = [2, 2] # 2 requests / 2s window

    hpk = h2(rand_bytes 32)
    _setup_keys hpk

    2.times { _send_count hpk; _success_response }
    _send_count hpk
    _fail_response :too_many_requests

    # Once the window expires, a fresh budget opens
    _setup_keys hpk # keep session keys warm past the tiny test session_timeout
    sleep 2.5
    _send_count hpk
    _success_response
  ensure
    Rails.configuration.x.relay.max_requests_per_seconds = save
  end

  # TTL-race regression: if the window expires between the limiter's SET NX
  # and INCR, the INCR resurrects the counter with no TTL — without a re-arm
  # the hpk would be rate-limited permanently. Simulate that poisoned state
  # and assert the limiter restores the TTL so the window still closes.
  test 'per-hpk rate limit re-arms a counter that lost its TTL' do
    save = Rails.configuration.x.relay.max_requests_per_seconds
    Rails.configuration.x.relay.max_requests_per_seconds = [3, 60]

    hpk = h2(rand_bytes 32)
    _setup_keys hpk

    key = "rate_#{hpk.to_b64}"
    $redis.set key, 100 # over budget with NO TTL, as the race leaves it

    _send_count hpk
    _fail_response :too_many_requests # still enforced while poisoned...
    assert_operator $redis.ttl(key), :>, 0,
      'limiter must re-arm the TTL so the counter cannot become permanent'
  ensure
    $redis.del "rate_#{hpk.to_b64}" if hpk
    Rails.configuration.x.relay.max_requests_per_seconds = save
  end

  private

  def _send_count(for_hpk)
    n = _make_nonce
    _post '/command', for_hpk, n, _client_encrypt_data(n, { cmd: 'count' })
  end

end
