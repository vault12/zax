# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

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

  # Enable Rack::Cache to put a simple HTTP cache in front of your application
  # Add `rack-cache` to your Gemfile before enabling this.
  # For large-scale production use, consider using a caching reverse proxy like
  # NGINX, varnish or squid.
  # config.action_dispatch.rack_cache = true

  # Disable serving static files from the `/public` folder by default since
  # Apache or NGINX already handles this.
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  # Compress JavaScripts and CSS.
  config.assets.js_compressor = :uglifier
  # config.assets.css_compressor = :sass

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Asset digests allow you to set far-future HTTP expiration dates on all assets,
  # yet still be able to expire them through the digest params.
  config.assets.digest = true

  # `config.assets.precompile` and `config.assets.version` have moved to config/initializers/assets.rb

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = 'X-Sendfile' # for Apache
  # config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect' # for NGINX

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Use the lowest log level to ensure availability of diagnostic information
  # when problems arise.
  config.log_level = :info

  # Prepend all log lines with the following tags.
  # config.log_tags = [ :subdomain, :uuid ]

  # Use a different logger for distributed setups.
  # config.logger = ActiveSupport::TaggedLogging.new(SyslogLogger.new)

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.action_controller.asset_host = 'http://assets.example.com'

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Send deprecation notices to registered listeners.
  config.active_support.deprecation = :notify

  # Use default logging formatter so that PID and timestamp are not suppressed.
  config.log_formatter = ::Logger::Formatter.new

  # Do not dump schema after migrations.
  # config.active_record.dump_schema_after_migration = false
end
