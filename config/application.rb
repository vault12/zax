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

    config.eager_load_paths += [
      "#{Rails.root}/lib", "#{Rails.root}/lib/helpers",
      "#{Rails.root}/lib/errors","#{Rails.root}/lib/tasks",
      "#{Rails.root}/app/jobs"]

    # --- Relay default configuration START ---
    config.x.relay.difficulty                 = 0 # 1...255 : require number of leading 0 bits in handshake

    # Various expiration timers in seconds, passed in
    # API calls to Redis

    config.x.relay.token_timeout              = 1.minutes
    config.x.relay.session_timeout            = 5.minutes
    config.x.relay.max_nonce_diff             = 1.minutes

    config.x.relay.nonce_timeout              = 10.minutes.seconds.to_i
    config.x.relay.mailbox_timeout            = 3.days.seconds.to_i
    config.x.relay.message_timeout            = 3.days.seconds.to_i

    # Retry count on mailbox and file storage redis transactions
    config.x.relay.mailbox_retry              = 5 # times

    # If present, set restart_window to return true when redis/nginx
    # or other dependent components are scheduled for restart.
    # Relay will sleep on requests until window is past and returns false.
    # Example: restart some components at hour boundary with @hourly cron job
    # config.x.relay.restart_window = lambda {
    #   t = DateTime.now
    #   t.minute == 0 and t.second<4
    # }
    # config.x.relay.restart_window_max_seconds = 5

    # === Dynamic session handshake difficulty throttling
    # Set period to 0 or omit to disable

    # Dynamic difficulty is calculated as
    # min_diff + round(diff_increase*log(request_count/min_requests,overload_factor))
    # request count = requests per last period + 1/2 of request previous period +
    # 1/3 requests of period before that

    # Period in minutes. Measure # of requests per period and adjust next period
    # config.x.relay.period = 15

    # Minimal number of requests. Thorttling will not trigger under this limit per period
    # config.x.relay.min_requests = 1000

    # Change factor leading to increase/decrease of difficulty
    # Factor of 2 means that for doubling of requests per period
    # from min_request level difficultiy will increase by one increment
    # config.x.relay.overload_factor = 2

    # Difficulty increase/decrease increment. Each unit is one bit of
    # zero leading handshake string. Setting say factor of 2 and increment
    # to 3 means that each doubling of traffic will require 3 extra zero-leading
    # bits in session handshake proof of work
    # config.x.relay.diff_increase = 1

    # === File Storage Managment
    config.x.relay.file_store = {

      # Set to false if you want to restrict your relay
      # from accepting file uploads. Realy will reject
      # all file related commands.
      enabled: true,

      # Operation mode: :normal or :test
      # In :test mode all file commands do not store actual
      # file data on hard drive at root: location. Instead file size
      # information is recorded, and downloadFileChunk command is
      # served with chunks filled with random entropy from /dev/urandom.
      # That allows relay file testing on large uploads/downloads without
      # spedning storage space

      mode: :normal, # or set to :test to skip saving files

      # Abs path for storage of file uploads.
      # Default: Rails.root/shared/uploads
      root: "#{Rails.root}/shared/uploads/",

      # Maximum size in bytes of storage folder. Relay
      # will start rejecting uploads when max size is reached.
      # -1 for unlimited
      # TBD: max_storage_bytes: -1,

      # String seed to generate unique storage file names.
      # If absent/empty it will be autogenerated and stored as
      # secret_seed.txt file in file_store.root. Storing as file
      # is recomended to have different seed at each relay.
      #
      # Changing this seed/file will prevent relay from corresponding
      # stored files with from/to mailboxes related to them.
      #
      secret_seed: "", # Empty to auto-generate secret_seed.txt on deploy

      # Maximum byte size of file chunks for upload/download ops
      # supported by this relay. Chunk size can not be bigger then
      # MAX_COMMAND_BODY in key_params.rb
      # Also used as max entropy size for getEntropy command
      max_chunk_size: 100 * 1024, # 100kb default

      # Default: files expire after 7 days
      files_expiration: 7.days.seconds.to_i,
    }

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
