# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Host authorization: the deployment sets ZAX_HOST to the relay hostname
  # (systemd unit); unset leaves hosts unrestricted.
  # See https://guides.rubyonrails.org/configuring.html#config-hosts for more information.
  config.hosts << ENV["ZAX_HOST"] if ENV["ZAX_HOST"].present?

  # Rails refuses to boot in production without a secret_key_base, but Zax
  # (API-only: no cookies, sessions or signed tokens) never signs anything
  # with it. A fresh random value per boot satisfies Rails without leaving a
  # secret to manage, deploy or leak; operators can still pin a stable key
  # via SECRET_KEY_BASE. If a future change uses Rails' signing stack
  # (signed cookies, message_verifier, generates_token_for, ...), a persisted
  # key shared across instances becomes mandatory — per-boot randomness
  # would invalidate signatures on every restart.
  config.secret_key_base = ENV["SECRET_KEY_BASE"] || SecureRandom.hex(64)

  # --- Relay default configuration START ---
  config.x.relay.difficulty                 = 2 # 1...255 : require number of leading 0 bits in handshake

  # If present, set restart_window to return true when redis/nginx
  # or other dependent components are scheduled for restart.
  # Relay will sleep on requests until window is past and returns false.
  # Example: restart components at hour boundary with @hourly cron job
  config.x.relay.restart_window = lambda {
    t = DateTime.now
    t.minute == 0 and t.second<4
  }
  config.x.relay.restart_window_max_seconds = 4

  # === Dynamic session handshake difficulty throttling
  # Period in minutes. Measure # of requests per period and adjust next period
  config.x.relay.period = 15 # 1 to test, 15 for production

  # Minimal number of requests. Thorttling wont trigger under this limit per period
  config.x.relay.min_requests = 1000 # 20 for test. 1000 for production

  # Change factor leading to increase/decrease of difficulty
  # Factor of 2 means that for doubling of requests per period
  # from min_request level difficultiy will increase by one increment
  config.x.relay.overload_factor = 2

  # Difficulty increase/decrease increment. Each unit is one bit of
  # zero leading handshake string. Setting say factor of 2 and increment
  # to 3 means that each doubling of traffic will require 3 extra zero-leading
  # bits in session handshake proof of work
  config.x.relay.diff_increase = 1

  # --- Relay default configuration END   ---
  # Code is not reloaded between requests.
  config.cache_classes = true

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available in either ENV["RAILS_MASTER_KEY"]
  # or in config/master.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # To disable serving Zax Dashboard or other static files from the `/public` folder,
  # or to handle this on Apache or NGINX level, uncomment the following line
  # config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  # Compress CSS using a preprocessor.
  # config.assets.css_compressor = :sass

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  # config.assets.compile = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # Include generic and useful information about system operation, but avoid logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII).
  config.log_level = :info

  # Prepend all log lines with the following tags.
  # config.log_tags = [ :request_id ]

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Use a real queuing backend for Active Job (and separate queues per environment).
  # config.active_job.queue_adapter     = :resque
  # config.active_job.queue_name_prefix = "zax_production"

  config.action_mailer.perform_caching = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = :notify

  # Use default logging formatter so that PID and timestamp are not suppressed.
  config.log_formatter = ::Logger::Formatter.new

  # Use a different logger for distributed setups.
  # require "syslog/logger"
  # config.logger = ActiveSupport::TaggedLogging.new(Syslog::Logger.new "app-name")

  if ENV["RAILS_LOG_TO_STDOUT"].present?
    # Preferred for systemd/container deploys: log to STDOUT and let
    # journald / the container runtime bound the size (see DEPLOYMENT_MANUAL.md).
    logger           = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  else
    # Limit on-disk log growth. Cap each file
    # and keep a fixed number of rotations; keep × size is the hard ceiling of
    # log disk use (here 10 × 100 MB ≈ 1 GB). Override via env for tuning.
    rotate_keep      = Integer(ENV.fetch("ZAX_LOG_ROTATE_KEEP", 10))
    rotate_size      = Integer(ENV.fetch("ZAX_LOG_ROTATE_SIZE", 100 * 1024 * 1024))
    log_file         = Rails.root.join("log", "#{Rails.env}.log")
    logger           = ActiveSupport::Logger.new(log_file, rotate_keep, rotate_size)
    logger.formatter = config.log_formatter
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  end
end
