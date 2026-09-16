# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'utils'
module Errors

  # Root class for our internal ZAX errors
  #
  # Relay internal errors will inherit from ZaxError.
  # Catch block handles 3 types of errors:
  # - RbNaCl::CryptoError for encryption
  # - ZaxError of relay own error conditions
  # - general errors from other libraries
  #
  # All known relay errors related to the protocol will return :bad_request.
  # No details of crypto errors are given to the client besides formatting
  # errors of a client request. Error details are logged
  # in the relay logs at :warning or :error levels depending on severity.
  #
  # :internal_server_error - a grave internal error that the
  # relay can not recover from on its own, usually related to
  # external services (such as RNG). The system administrator should
  # investigate these errors, they are always logged at ERROR level.
  # Clients get a response with :internal_server_error code so that
  # they may avoid using given relay for the time being.

  class ZaxError < StandardError
    include Utils

    def initialize(ctrl, data = nil)
      @controller = ctrl
      @data = data
      @response_code = :bad_request
    end

    # Human-readable detail supplied at raise time (msg:); `message` itself
    # defaults to the class name since initialize doesn't call super.
    def msg
      (@data.is_a?(Hash) && @data[:msg]) ? @data[:msg] : self.class.name
    end

    # Client-facing X-Error-Details text. Generic by default so failures stay
    # indistinguishable (no oracle); a subclass may override to deliberately
    # inform the client of a specific, safe-to-reveal condition (e.g. mailbox full).
    def client_detail
      'Your request can not be completed.'
    end

    # Name of the rejection for the operator's own counts
    # (ApplicationController#report_rejection): the error class by default,
    # or the reason: a raise site passes to split one class into distinct
    # conditions (a nonce from a skewed clock vs a replayed one). A fixed
    # vocabulary, never built from client input, never sent to the client.
    def reason
      (@data.is_a?(Hash) && @data[:reason]) || self.class.name.demodulize.delete_suffix('Error')
    end

    # Coarse group of a reason, for the operator's overview
    # (ApplicationController#report_rejection):
    #   limit     - a relay policy said no: rate limit, quotas, caps, no file store
    #   device    - one device with a problem of its own: clock, keys, replay
    #   session   - protocol churn: sessions and handshakes that have ended
    #   malformed - not the protocol: scanners, foreign clients, client bugs
    # Crypto, Argument and FilesDisabled are the rejections that are not
    # ZaxErrors (RbNaCl and Ruby exceptions rescued in reportCommonErrors,
    # and the 405 answered in CommandController#check_filemanager). An
    # unlisted name comes out as 'other', so a new error class is noticed,
    # not hidden.
    KINDS = {
      'RateLimit' => 'limit', 'QuotaExceeded' => 'limit', 'MailboxFull' => 'limit',
      'SenderCap' => 'limit', 'FileSizeLimit' => 'limit', 'FilesDisabled' => 'limit',
      'ClockSkew' => 'device', 'Crypto' => 'device', 'NonceReplay' => 'device',
      'NoSession' => 'session', 'NoHandshake' => 'session', 'ClientToken' => 'session',
      'Body' => 'malformed', 'Hpk' => 'malformed', 'Argument' => 'malformed',
      'Report' => 'malformed', 'RelayToken' => 'malformed', 'Nonce' => 'malformed'
    }.freeze

    def self.kind_of(reason)
      KINDS.fetch(reason, 'other')
    end

    # Extra headers a subclass adds to its failure response, in head() option
    # form (:retry_after becomes Retry-After). Empty for the common case.
    def extra_headers
      {}
    end

    def http_fail
      # No information about the relay state is sent back to the client for known error conditions
      if @controller and @controller.class < ApplicationController
        @controller.expires_now
        xerr = @response_code != :internal_server_error ? client_detail : 'Something is wrong with this relay. Try again later.'
        @controller.head @response_code, { x_error_details: xerr }.merge(extra_headers)
      end
      @err_msg = ( @data and @data.is_a?(Hash) and @data[:msg] ) ? @data[:msg] : ''
      warn "#{INFO_NEG} #{@err_msg}"

      # WATCH cleanup on error paths is handled by runRedisTransaction's `ensure` (conn.unwatch before the connection returns to the pool)
    end

    # Used when the relay's internal integrity is in doubt.
    # Both args optional: error classes call this with just a note (no
    # exception). The old signature (optional note BEFORE required excpt)
    # bound a lone String to excpt and crashed on excpt.backtrace.
    def severe_error(note = '', excpt = nil)
      # performed? guard: http_fail may already have rendered (e.g.
      # ServerRandomError#http_fail renders 500, then calls severe_error to
      # log) — a second head would raise DoubleRenderError
      if @controller and @controller.class < ApplicationController and not @controller.performed?
        @controller.expires_now
        @controller.head :internal_server_error,
          x_error_details: 'Something is wrong with this relay. Try again later.'
      end
      _log_exception ERROR,note,excpt
      # The one condition worth external telemetry (no-op unless Sentry is
      # enabled). The note stays local on the exception path: it went through
      # add_error_context, which appends the client's hpk.
      if excpt
        Sentry.capture_exception excpt
      else
        Sentry.capture_message note.gsub(/\e\[[0-9;]*m/, ''), level: :error
      end
    end

    # This is used to log general non-ZAX exceptions
    def report(note, excpt)
      # handle non-ZAX errors, such as encoding, etc.
      @controller.expires_now
      @controller.head @response_code,
        x_error_details: 'Your request can not be completed.'
      _log_exception WARN,note,excpt
    end

    # This is used to log RbNaCl errors
    def NaCl_error(e)
      e1 = e.is_a?(RbNaCl::BadAuthenticatorError) ? 'The authenticator was forged or otherwise corrupt' : ''
      e2 = e.is_a?(RbNaCl::BadSignatureError) ? 'The signature was forged or otherwise corrupt' : ''
      # never log the raw request body. Log summary: byte length + a short hex prefix.
      body = @controller.respond_to?(:body) ? @controller.body.to_s : ''
      error "#{ERROR} Decryption error for packet: "\
        "#{e1}#{e2} "\
        "body #{body.bytesize}B prefix=#{toHex body.byteslice(0, LOG_BODY_PREFIX)}"
      _log_exception ERROR, "Stack trace", e

      @controller.head @response_code,
        x_error_details: 'Your request can not be completed.'
    end

    # === Exception loging functions ===
    def _log_exception(icon, note, excpt)
      warn "#{icon} #{note}:\n#{EXPT} \xE2\x94\x8C#{excpt} \xE2\x94\x90"
      # no exception object (or one that was never raised): nothing to trace
      trace = excpt.respond_to?(:backtrace) ? excpt.backtrace : nil
      return unless trace
      warn trace[0..7].reduce("") { |s,x|
        s += "#{EXPT} \xE2\x94\x9C#{x}\n" } +
      "#{EXPT} \xE2\x94\x94#{BAR*25}\xE2\x94\x98"
    end

    def log_message(m)
      #  "#{m}:\n#{dumpHex @data}:\n#{EXPT} #{self}\n---"
      "#{m}"
    end

    def info(m)
      Rails.logger.info log_message m
      # @controller.logger.info log_message m
    end

    def warn(m)
      Rails.logger.warn log_message m
      # @controller.logger.warn log_message m
    end

    def error(m)
      Rails.logger.error log_message m
    end
  end
end
