# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require File.expand_path('../boot', __FILE__)

# require 'rails/all'
# removed active record until we need DB (if ever)
# uncomment #### lines when putting active_record back (or 'rails/all')

require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'sprockets/railtie'
require 'rails/test_unit/railtie'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Zax
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    config.encoding = 'utf-8'

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    # Do not swallow errors in after_commit/after_rollback callbacks.
    #### config.active_record.raise_in_transactional_callbacks = true

    config.eager_load_paths += ["#{Rails.root}/lib"]

    # --- Relay default configuration START ---
    config.x.relay.difficulty                 = 0 # 1...255 : require number of leading 0 bits in handshake

    config.x.relay.token_timeout              = 1.minutes
    config.x.relay.session_timeout            = 5.minutes
    config.x.relay.max_nonce_diff             = 1.minutes
    # in seconds for redis
    config.x.relay.nonce_timeout              = 10.minutes.seconds.to_i
    config.x.relay.mailbox_timeout            = 3.days.seconds.to_i
    config.x.relay.message_timeout            = 3.days.seconds.to_i

    config.x.relay.mailbox_retry              = 5 # times

    config.cache_store = :redis_store, {
      :host => 'localhost',
      :port => 6379,
      :db => 1,
#     :password => 'mysecret',
      :namespace => 'cache',
      :expires_in => 10.minutes }

    # --- Relay default configuration END ---
  end
end
