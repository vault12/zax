# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

# Telemetry is opt-in per relay: without SENTRY_DSN in the environment the
# SDK is disabled and nothing ever leaves the machine. With a DSN the relay
# reports two things and only two:
#   * its own failures — unexpected exceptions, Redis trouble, job crashes —
#     as Sentry errors (ZaxError#severe_error);
#   * every request it rejected with a 4xx, as one metric point carrying the
#     status, the reason and its kind (ZaxError#reason, ZaxError.kind_of),
#     the route, the command and, once the request has proved it holds the
#     session, a keyed hash of the sender's key; plus a log line for that
#     named sender, capped per sender (ApplicationController#report_rejection).
#     Protocol violations are client-forgeable, so they are counted, never
#     turned into errors.
Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.enabled_environments = %w[production]
  # A privacy relay reports its own health, never its clients: no IPs, no
  # request bodies, no log-line breadcrumbs (log lines carry hpk) and no hpk
  # in the rejection counts — only a truncated hash of it.
  config.send_default_pii = false
  config.breadcrumbs_logger = []
  # Protocol errors are answered in reportCommonErrors and never signal relay
  # trouble; keep them out of error reports even if one leaks from a background job.
  config.excluded_exceptions += %w[Errors::ZaxError]
  # Rejection counts go out as structured logs (off by default in the SDK)
  # and metrics (on by default). Only the relay's own log lines: with logs
  # enabled, sentry-rails would otherwise ship one line per request — every
  # served command, with its path and timing — which is traffic, not signal.
  config.enable_logs = true
  config.rails.structured_logging.enabled = false
  # The relay's public hostname labels everything sent, instead of the
  # machine's own name.
  config.server_name = ENV['ZAX_HOST'] if ENV['ZAX_HOST'].present?
  # A deployed relay is a git checkout — tag events with the running commit
  sha = (Dir.chdir(Rails.root) { `git rev-parse --short HEAD 2>/dev/null` }.strip rescue '')
  config.release = sha unless sha.empty?
end
