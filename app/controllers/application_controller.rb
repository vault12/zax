# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class ApplicationController < ActionController::API
  include ResponseHelper
  before_action :check_restart_window
  before_action :allow_origin
  before_action :check_stale_files
  # Controller-rendered 4xx only: a 403 from Rails host authorization is
  # answered by middleware and never gets here (report_rejection)
  after_action :report_rejection, if: -> { response.status.between?(400, 499) }

  public

  def check_restart_window
    rw = Rails.configuration.x.relay.restart_window
    return unless rw
    counter = Rails.configuration.x.relay.restart_window_max_seconds || 10
    while rw.call and counter > 0
      sleep 1
      counter -= 1
    end
  end

  def allow_origin
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Headers'] = 'Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Session-ID,Content-Type,Content-Range,Content-Disposition';
    # let browser-context clients read the rejection reason and the 429 retry
    # timing (glow.ts attaches both to GlowNetworkError); native transports
    # see them regardless
    headers['Access-Control-Expose-Headers'] = 'X-Error-Details,Retry-After';
    headers['Cache-Control'] = "no-transform," + ( headers['Cache-Control'] || "")
  end

  # Traffic-driven stale-file sweep trigger. One integer compare in memory; must never fail a client request.
  def check_stale_files
    FilesCheck.maybe_run
  rescue StandardError => e
    logger.warn "#{WARN} FilesCheck trigger failed: #{e.message}"
  end

  protected

  # Relay-wide ceiling on the handshake path. GLOBAL by way of a single Redis counter. Used as a before_action on Session/Proof 
  def check_global_handshake_limit
    limit = Rails.configuration.x.relay.max_global_requests_per_seconds
    return unless limit
    max, window = limit

    key = 'rate_global_handshake'
    $redis.set(key, 0, ex: window, nx: true) # create window + TTL once
    count = $redis.incr(key)
    # If the window expired between SET NX and INCR, the INCR resurrected the
    # counter with NO TTL — re-arm it so the window always closes and the
    # counter can never become a permanent 503.
    $redis.expire(key, window) if $redis.ttl(key) < 0
    if count.to_i > max
      Errors::GlobalLimitError.new(self, msg: "global handshake limit: over #{max}/#{window}s").http_fail
    end
  end

  def add_error_context(l)
    l =  "#{RED}#{l}#{ENDCLR}"
    l += " #{CMD}#{GREEN}#{@cmd}#{ENDCLR}" if @cmd
    l += " hpk: #{MAGENTA}'#{dumpHex @hpk}'#{ENDCLR}" if @hpk
    return l
  end

  # Every 4xx a controller answers is counted in Sentry as one
  # relay.rejection metric point carrying the status, the reason (the
  # relay's own name for the rejection, set in reportCommonErrors) and its
  # kind, the route, the command and a hash of the sender key — never the
  # hpk, the body or the address. Answers from outside the controllers are
  # not: the 403 of host authorization and nginx's 413 are refused before
  # any of this runs, and a relay without SENTRY_DSN does none of this
  # work, not even the Redis counter below. The sender is named only once
  # the request has proved it holds the session
  # (the command box opened, CommandController#process_cmd): until then the
  # hpk in the preamble is anyone's claim, and a forged one must not put a
  # rejection on another device's record or mint a new sender per request.
  #
  # A log line, for one device's timeline, is written only for a named
  # sender and at most rejection_log_cap times per sender per window. So a
  # flood of garbage on /command, which is refused before any rate limit,
  # costs metric points and nothing else, and a device refused a hundred
  # times a minute tells its story in the first ten lines while the metric
  # still counts all hundred. The metric points are sent as they are, one
  # per rejection: the SDK ships points, not sums, and we deliberately do
  # not sum them here. Without a sender they carry no per-request
  # cardinality, their volume is a quota knob in Sentry's own settings, and
  # a local aggregator would add a counter, a flush timer and a
  # thread-safety story to guard a bill. 5xx are not counted here: those
  # are relay failures and reach Sentry as errors with full context.
  def report_rejection
    return unless Sentry.initialized? && Sentry.configuration.sending_allowed?
    sender = @sender && sender_hash(@sender)
    attributes = {
      status: response.status,
      kind: (@rejection && ZaxError.kind_of(@rejection)),
      reason: @rejection,
      route: request.path,
      cmd: @cmd,
      sender: sender
    }.compact
    Sentry.metrics.count('relay.rejection', attributes: attributes)
    Sentry.logger.warn('relay rejected request', **attributes) if sender && under_log_cap?(sender)
  end

  # The sender attribute: an HMAC of the hpk, truncated, keyed with the
  # file-store seed — a secret this relay already keeps for life (changing
  # it orphans stored files). The same device therefore gets the same value
  # on this relay for as long as the relay exists, only the relay can
  # compute it (to Sentry, and to anyone with a list of public keys, the
  # value is opaque), and two relays name one device differently unless
  # they share ZAX_SECRET_SEED. A relay without a file store has no seed
  # and falls back to secret_key_base, random per boot unless SECRET_KEY_BASE
  # is set, so its values hold until the next restart.
  def sender_hash(hpk)
    key = Rails.configuration.x.relay.file_store[:secret_seed].presence || Rails.application.secret_key_base
    OpenSSL::HMAC.hexdigest('SHA256', key, hpk)[0, 16]
  end

  # One Redis counter per sender per window, shared by all workers, same
  # pattern as the rate limit. Redis trouble of any kind — a Redis error or
  # the pool's own timeout, which is not one — must not fail a request that
  # has already been answered: it lets the line through instead.
  def under_log_cap?(sender)
    max, window = Rails.configuration.x.relay.rejection_log_cap
    return true unless max
    key = "rejlog_#{sender}"
    $redis.set(key, 0, ex: window, nx: true)
    count = $redis.incr(key)
    $redis.expire(key, window) if $redis.ttl(key) < 0
    count.to_i <= max
  rescue StandardError => e
    logger.warn "#{WARN} rejection log cap unavailable: #{e.message}"
    true
  end

  def reportCommonErrors(context_label)
    yield
    rescue RbNaCl::CryptoError => e
      @rejection = 'Crypto'
      logger.error add_error_context(context_label)
      ZaxError.new(self).NaCl_error e
    rescue Redis::CommandError => e
      # Redis failing is relay infrastructure trouble, not a client mistake —
      # report it to the operator (no-op unless Sentry is enabled)
      Sentry.capture_exception e
      logger.error add_error_context(context_label)
      TransactionError.new(self,
        { hpk: @hpk,
          msg: "#{RED}Redis error:#{ENDCLR} #{e}"
        }).http_fail
    rescue ZaxError => e
      @rejection = e.reason
      logger.error add_error_context(context_label)
      e.http_fail
      # A ZaxError raised outside a controller (Mailbox quota) carries no controller ref, http_fail logs but renders nothing
      unless performed? # render :bad_request if internal error
        expires_now
        head :bad_request, x_error_details: e.client_detail
      end
    rescue ArgumentError => e
      @rejection = 'Argument'
      ReportError.new(self).report add_error_context(context_label), e
    rescue => e
      ZaxError.new(self).severe_error add_error_context(context_label),e
  end
end
