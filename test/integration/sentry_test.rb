# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

# Guards the reporting policy, not the SDK. Two things may reach Sentry:
# relay-side failures as errors, and rejected requests as counts — one
# metric point per 4xx, carrying the status, the reason and its kind, the
# route, the command and, once the request has proved it holds the session,
# a keyed hash of the sender key, plus a log line for that named sender,
# capped per sender. Anything a client can produce at will must never become
# an error, and the sender key itself must never leave the machine. The negative checks ARE that policy — they fail if capture is
# ever added to the protocol-error branches, if exceptions start bubbling
# into the Rails middleware where sentry-rails auto-captures, or if the hpk
# shows up in a count. CI is the only place this is checked (live relays
# prove delivery, not non-delivery). The positive tests double as the
# control that makes the assert_empty checks meaningful: with a
# misconfigured, permanently-silent SDK they would fail first.
#
# The initializer keeps Sentry disabled outside production, so each test
# re-inits the SDK with an in-memory transport — nothing is sent anywhere.
class SentryTest < ActionDispatch::IntegrationTest
  setup do
    Sentry.init do |config|
      config.dsn = 'https://fake@sentry.localdomain/1'
      config.enabled_environments = %w[test]
      config.background_worker_threads = 0 # capture inline, no worker thread
      config.transport.transport_class = Sentry::DummyTransport
      config.enable_logs = true # off by default in the SDK; the initializer turns it on
    end
  end

  teardown do
    Sentry.close
  end

  def sentry_events
    Sentry.get_current_client.transport.events
  end

  # Logs and metrics wait in SDK buffers until a flush; returns the envelope
  # items of one kind with attribute names normalized to strings.
  def sentry_items(kind)
    client = Sentry.get_current_client
    client.flush
    client.transport.envelopes.flat_map(&:items)
      .select { |item| item.headers[:type] == kind }
      .flat_map { |item| item.payload[:items] }
      .map { |item| item.merge(attributes: item[:attributes].transform_keys(&:to_s)) }
  end

  def sentry_logs
    sentry_items 'log'
  end

  def sentry_metrics
    sentry_items 'trace_metric'
  end

  # The attributes the relay sets itself, without the SDK's own (environment, release, sdk)
  def relay_attributes(item)
    item[:attributes].transform_values { |a| a[:value] }.slice('status', 'kind', 'reason', 'route', 'cmd', 'sender')
  end

  # A command from hpk as the client would send it, with a fresh nonce
  def _send(hpk, data)
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
  end

  def _send_count(hpk)
    _send hpk, cmd: 'count'
  end

  # The sender attribute as the relay computes it: an HMAC of the hpk keyed
  # with the file-store seed, truncated (ApplicationController#sender_hash)
  def sender_of(hpk)
    seed = Rails.configuration.x.relay.file_store[:secret_seed]
    assert seed.present?, 'the file-store seed is established at boot'
    OpenSSL::HMAC.hexdigest('SHA256', seed, hpk)[0, 16]
  end

  test 'severe_error reports the exception to Sentry' do
    Errors::ZaxError.new(nil).severe_error 'sentry hook test', RuntimeError.new('boom')
    assert_equal 1, sentry_events.length
    exception = sentry_events.first.to_h[:exception][:values].first
    assert_equal 'RuntimeError', exception[:type]
    # sentry-ruby renders the value via Exception#detailed_message: "boom (RuntimeError)"
    assert_includes exception[:value], 'boom'
  end

  test 'severe_error without an exception reports the note, colors stripped' do
    Errors::ZaxError.new(nil).severe_error "\e[0;31mConfiguration error\e[0m"
    assert_equal 1, sentry_events.length
    assert_equal 'Configuration error', sentry_events.first.to_h[:message]
  end

  test 'protocol violations are counted, never reported as errors' do
    post '/command', params: 'garbage that is not a zax packet'
    _fail_response :bad_request
    assert_empty sentry_events

    assert_equal 1, sentry_metrics.length
    metric = sentry_metrics.first
    assert_equal 'relay.rejection', metric[:name]
    assert_equal 'counter', metric[:type].to_s
    assert_equal 1, metric[:value]
    # nothing is known about the sender or the command before the packet parses
    assert_equal({ 'status' => 400, 'kind' => 'malformed', 'reason' => 'Body', 'route' => '/command' }, relay_attributes(metric))
    # and with no sender to drill into there is no log line: garbage costs a metric point, nothing more
    assert_empty sentry_logs
  end

  test 'a rate-limited command is counted with the command and a keyed hash of the sender' do
    save = Rails.configuration.x.relay.max_requests_per_seconds
    Rails.configuration.x.relay.max_requests_per_seconds = [1, 60]
    hpk = h2(rand_bytes 32)
    _setup_keys hpk

    _send_count hpk
    _success_response
    _send_count hpk
    _fail_response :too_many_requests

    expected = { 'status' => 429, 'kind' => 'limit', 'reason' => 'RateLimit', 'route' => '/command', 'cmd' => 'count',
                 'sender' => sender_of(hpk) }
    assert_equal 1, sentry_logs.length, 'only the rejected command is counted'
    log = sentry_logs.first
    assert_equal 'relay rejected request', log[:body]
    assert_equal 'warn', log[:level]
    assert_equal expected, relay_attributes(log)
    assert_equal 1, sentry_metrics.length
    assert_equal expected, relay_attributes(sentry_metrics.first)

    # the key itself never leaves the machine, in any encoding, and neither
    # does anything computable from the key alone: the hash is keyed by the relay
    sent = (sentry_logs + sentry_metrics).to_json
    assert_not_includes sent, hpk.to_b64
    assert_not_includes sent, hpk.unpack1('H*')
    assert_not_includes sent, Digest::SHA256.hexdigest(hpk)[0, 16]
  ensure
    Rails.configuration.x.relay.max_requests_per_seconds = save
  end

  # A relay without a file store has no seed; the hash is then keyed with
  # secret_key_base, random per boot unless SECRET_KEY_BASE is set
  test 'without a file-store seed the sender hash is keyed with secret_key_base' do
    relay = Rails.configuration.x.relay
    saved = relay.file_store[:secret_seed]
    relay.file_store[:secret_seed] = ''
    hpk = h2(rand_bytes 32)
    _setup_keys hpk
    _send hpk, cmd: 'bogus'
    _fail_response :bad_request
    expected = OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, hpk)[0, 16]
    assert_equal expected, relay_attributes(sentry_metrics.first)['sender']
  ensure
    relay.file_store[:secret_seed] = saved
  end

  # Without a DSN the relay is opted out of telemetry and must do none of
  # the work, not even the Redis counter behind the log cap
  test 'a relay without a Sentry DSN does no telemetry work' do
    Sentry.init do |config|
      config.dsn = nil
      config.enabled_environments = %w[test]
      config.background_worker_threads = 0
      config.transport.transport_class = Sentry::DummyTransport
      config.enable_logs = true
    end
    save = Rails.configuration.x.relay.max_requests_per_seconds
    Rails.configuration.x.relay.max_requests_per_seconds = [1, 60]
    hpk = h2(rand_bytes 32)
    _setup_keys hpk
    _send_count hpk
    _success_response
    _send_count hpk
    _fail_response :too_many_requests
    assert_not $redis.exists?("rejlog_#{sender_of(hpk)}"), 'no log-cap counter without a DSN'
    assert_empty sentry_logs
    assert_empty sentry_metrics
  ensure
    Rails.configuration.x.relay.max_requests_per_seconds = save
  end

  # The cap runs in an after_action, after the answer is rendered: Redis
  # trouble there lets the line through and never fails the request. The
  # pool's timeout is not a Redis error, so it is covered on its own
  test 'the log cap fails open when Redis is unavailable' do
    controller = ApplicationController.new
    real = $redis
    [ConnectionPool::TimeoutError, Redis::CannotConnectError].each do |error|
      # the pool wrapper is a BasicObject, so swap the handle instead of stubbing it
      $redis = Object.new
      $redis.define_singleton_method(:set) { |*| raise error, 'redis is away' }
      assert controller.send(:under_log_cap?, 'deadbeefdeadbeef'), "#{error} must let the line through"
    end
  ensure
    $redis = real
  end

  # Log lines are for one device's timeline and capped per sender; the
  # metric counts every rejection
  test 'log lines per sender are capped, the metric counts every rejection' do
    relay = Rails.configuration.x.relay
    saved = [relay.max_requests_per_seconds, relay.rejection_log_cap]
    relay.max_requests_per_seconds = [1, 60]
    relay.rejection_log_cap = [2, 60]
    hpk = h2(rand_bytes 32)
    _setup_keys hpk
    _send_count hpk
    _success_response
    4.times do
      _send_count hpk
      _fail_response :too_many_requests
    end
    assert_equal 4, sentry_metrics.length
    assert_equal [sender_of(hpk)] * 2, sentry_logs.map { |log| relay_attributes(log)['sender'] }
  ensure
    relay.max_requests_per_seconds, relay.rejection_log_cap = saved
  end

  # The sender is named only after the command box opened. A rejection before
  # that carries no sender and gets no log line, so a forged preamble cannot
  # put rejections on another device's record, mint a fresh sender per
  # request or fill the log; the same session is named as soon as it is
  # rejected after decryption.
  test 'a rejection before the box opens carries no sender and no log line' do
    victim = h2(rand_bytes 32) # never had a session
    _post '/command', victim, _make_nonce, rand_bytes(64)
    _fail_response :bad_request

    hpk = h2(rand_bytes 32)
    _setup_keys hpk
    # a stale nonce is refused before the box is opened
    n = _make_nonce(Time.now.to_i - 120)
    _post '/command', hpk, n, _client_encrypt_data(n, cmd: 'count')
    _fail_response :bad_request
    # the same session, rejected after decryption: named
    _send hpk, cmd: 'bogus'
    _fail_response :bad_request
    # a box the relay cannot open proves nothing
    @session_key = RbNaCl::PrivateKey.generate
    _send hpk, cmd: 'count'
    _fail_response :bad_request

    named = sender_of(hpk)
    seen = sentry_metrics.map { |item| relay_attributes(item).values_at('reason', 'sender') }
    assert_equal [['NoSession', nil], ['ClockSkew', nil], ['Report', named], ['Crypto', nil]], seen
    assert_equal [['Report', named]], sentry_logs.map { |item| relay_attributes(item).values_at('reason', 'sender') }
    # the forged hpk leaves no trace at all, not even hashed
    assert_not_includes (sentry_logs + sentry_metrics).to_json, sender_of(victim)
  end

  # A relay without a file store answers file commands with 405 straight from
  # the controller, outside reportCommonErrors; the count still names it
  test 'a file command on a relay without a file store is counted as FilesDisabled' do
    relay = Rails.configuration.x.relay
    saved = relay.file_store[:enabled]
    relay.file_store[:enabled] = false
    hpk = h2(rand_bytes 32)
    _setup_keys hpk
    _send hpk, cmd: 'fileStatus', uploadID: 'x'
    assert_response :method_not_allowed

    expected = { 'status' => 405, 'kind' => 'limit', 'reason' => 'FilesDisabled', 'route' => '/command',
                 'cmd' => 'fileStatus', 'sender' => sender_of(hpk) }
    assert_equal [expected], sentry_logs.map { |log| relay_attributes(log) }
    assert_equal [expected], sentry_metrics.map { |metric| relay_attributes(metric) }
  ensure
    relay.file_store[:enabled] = saved
  end

  # The reason is the relay's own fixed name for what went wrong and the kind
  # its coarse group, so the counts can be split into conditions worth acting
  # on (quota, clock skew) and expected churn (a session that has ended). One
  # case per name.
  test 'each rejection is counted under a fixed name for its reason and its kind' do
    relay = Rails.configuration.x.relay
    saved = [relay.max_messages, relay.file_store[:max_storage_bytes], relay.file_store[:max_file_size]]
    # keep max_file_size <= the shrunken quota or FileManager refuses to boot
    relay.file_store[:max_storage_bytes] = 1000
    relay.file_store[:max_file_size] = 1000

    counted = 0
    logged = 0
    # named: the box opened, so the sender is known and the rejection also gets a log line
    expect = lambda do |status, reason, kind, route = '/command', named: true|
      _fail_response status
      counted += 1
      logged += 1 if named
      logs, metrics = sentry_logs, sentry_metrics
      assert_equal counted, metrics.length, "one metric per rejection (#{reason})"
      assert_equal logged, logs.length, "a log line only for a named sender (#{reason})"
      (named ? [logs, metrics] : [metrics]).each do |items|
        assert_equal({ 'reason' => reason, 'kind' => kind, 'route' => route },
                     relay_attributes(items.last).slice('reason', 'kind', 'route'))
        assert_equal named, relay_attributes(items.last).key?('sender'), "sender only after the box opened (#{reason})"
      end
    end

    hpk = h2(rand_bytes 32)
    to = h2(rand_bytes 32).to_b64
    _setup_keys hpk

    # a command the relay does not know
    _send hpk, cmd: 'bogus'
    expect.call :bad_request, 'Report', 'malformed'

    # the same nonce twice
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, cmd: 'count')
    _success_response
    _post '/command', hpk, n, _client_encrypt_data(n, cmd: 'count')
    expect.call :bad_request, 'NonceReplay', 'device'

    # a nonce stamped two minutes ago: the sender's clock is off
    n = _make_nonce(Time.now.to_i - 120)
    _post '/command', hpk, n, _client_encrypt_data(n, cmd: 'count')
    expect.call :bad_request, 'ClockSkew', 'device', named: false

    # a file bigger than the relay accepts, then one that would overflow the
    # sender quota. A fresh metadata nonce per declaration: a reused one is
    # rejected as a replay before the quota is looked at
    meta = -> { { ctext: 'x', nonce: rand_bytes(24).to_b64 } }
    _send hpk, cmd: 'startFileUpload', to: to, file_size: 1001, metadata: meta.call
    expect.call :bad_request, 'FileSizeLimit', 'limit'
    _send hpk, cmd: 'startFileUpload', to: to, file_size: 600, metadata: meta.call
    _success_response
    _send hpk, cmd: 'startFileUpload', to: to, file_size: 600, metadata: meta.call
    expect.call :bad_request, 'QuotaExceeded', 'limit'

    # the sender's own message cap, then the recipient's full mailbox (seen
    # by another sender). Both caps count live messages and a file
    # declaration is one, so this runs with a fresh sender and recipient
    relay.max_messages = 1
    box = h2(rand_bytes 32).to_b64
    sender = h2(rand_bytes 32)
    _setup_keys sender
    _send sender, cmd: 'upload', to: box, payload: 'one'
    _success_response
    _send sender, cmd: 'upload', to: box, payload: 'two'
    expect.call :bad_request, 'SenderCap', 'limit'
    other = h2(rand_bytes 32)
    _setup_keys other
    _send other, cmd: 'upload', to: box, payload: 'three'
    expect.call :bad_request, 'MailboxFull', 'limit'

    # a command boxed with keys the relay does not hold
    @session_key = RbNaCl::PrivateKey.generate
    _send other, cmd: 'count'
    expect.call :bad_request, 'Crypto', 'device', named: false

    # a command after the session is gone
    _delete_keys other
    _send other, cmd: 'count'
    expect.call :bad_request, 'NoSession', 'session', named: false

    # verify_session for a handshake that was never started, or has expired
    _post '/verify_session', h2(rand_bytes 32), rand_bytes(32)
    expect.call :unauthorized, 'NoHandshake', 'session', '/verify_session', named: false

    # a name nobody mapped shows up as 'other' instead of vanishing into a group
    assert_equal 'other', ZaxError.kind_of('SomethingNew')
  ensure
    relay.max_messages, relay.file_store[:max_storage_bytes], relay.file_store[:max_file_size] = saved
  end

  # Scanner traffic on unknown paths never reaches the counts: the relay
  # answers 503 by design ("pretend we are dead") and 5xx are not
  # rejections. (A wrong body on a real route is a protocol violation like
  # any other: counted as Body, without a sender.)
  test 'unknown paths are neither counted nor reported' do
    get '/wp-login.php'
    assert_response :service_unavailable
    post '/wp-login.php', params: 'log=admin&pwd=admin'
    assert_response :service_unavailable
    assert_empty sentry_events
    assert_empty sentry_logs
    assert_empty sentry_metrics
  end

  test 'a served command leaves no trace in Sentry' do
    hpk = h2(rand_bytes 32)
    _setup_keys hpk
    _send_count hpk
    _success_response
    assert_empty sentry_events
    assert_empty sentry_logs
    assert_empty sentry_metrics
  end
end
