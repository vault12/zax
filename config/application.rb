# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
# require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Zax
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0
    config.encoding = 'utf-8'

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.eager_load_paths += [Rails.root.join("lib"), Rails.root.join("app/jobs"), Rails.root.join("app/services")]

    # --- Relay default configuration START ---
    config.x.relay.difficulty                 = 0 # 1...255 : require number of leading 0 bits in handshake

    # Various expiration timers in seconds, passed in
    # API calls to Redis

    config.x.relay.token_timeout              = 1.minute
    config.x.relay.session_timeout            = 20.minutes
    config.x.relay.max_nonce_diff             = 1.minutes

    config.x.relay.nonce_timeout              = 10.minutes.seconds.to_i
    config.x.relay.mailbox_timeout            = 5.days.seconds.to_i
    config.x.relay.message_timeout            = 5.days.seconds.to_i

    # Hard cap on the number of live messages a single originator (sender hpk)
    # may keep stored across all recipient mailboxes. Set to nil to disable the cap.
    config.x.relay.max_messages               = 500

    # Per-hpk command rate limit as [max_requests, window_seconds]: a fixed
    # window opens at the sender's first command and allows max_requests until
    # window_seconds elapse, when a fresh budget opens.
    # The budget must cover the relay's own file protocol: every 500kb chunk
    # of a file is one uploadFileChunk command, the Guard client runs up to
    # 3 chunk streams in parallel (~20 commands/s at full speed) and polls
    # its mailbox alongside. Keep the window short — a client that does hit
    # the limit stays blocked until the window expires.
    # Set to nil to disable.
    config.x.relay.max_requests_per_seconds   = [1200, 60]

    # Sentry log lines per sender as [max_lines, window_seconds]
    # (ApplicationController#report_rejection). A rejected request is always
    # counted in the relay.rejection metric; the log line, meant for one
    # device's timeline, is written only for a sender the relay has verified
    # and at most this often per sender, so a device that is refused a
    # hundred times a minute costs a hundred metric points and ten lines.
    config.x.relay.rejection_log_cap          = [10, 60]

    # Relay-WIDE ceiling on the handshake path (/start_session, /verify_session, /prove) as [max_requests, window_seconds]. One global Redis counter (shared
    # across all Puma workers), enforced before any RNG/keygen/ECDH work. Over the ceiling => 503 (retry later).
    # Set to nil to disable.
    config.x.relay.max_global_requests_per_seconds = [10_000, 10]

    # Period stale-file sweep (FilesCleanupJob) runs.
    # First request past the interval triggers one background sweep (lib/files_check.rb)
    # nil disables.
    config.x.relay.stale_file_check           = 12.hours.to_i

    # Retry count on mailbox and file storage redis transactions
    config.x.relay.mailbox_retry              = 5 # times

    # If present, set restart_window to return TRUE when redis/nginx
    # or any other dependent components are scheduled for restart.
    # Relay will sleep on requests until window is past and returns false.
    # Example: restart some components at hour boundary with @hourly cron job
    # config.x.relay.restart_window = lambda {
    #   t = DateTime.now
    #   t.minute == 0 and t.second<4
    # }
    config.x.relay.restart_window_max_seconds = 5

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
      # spending storage space

      mode: :normal, # or set to :test to skip saving files

      # Abs path for storage of file uploads.
      # Default: Rails.root/shared/uploads
      root: "#{Rails.root}/shared/uploads/",

      # Per-sender storage quota: total declared bytes of one hpk's live
      # files; startFileUpload is rejected if the sender would exceed it.
      # Sized for the Vault12 app's own fan-out: a Shamir shard equals the
      # full asset size, one shard per guardian, and the owner hpk stores
      # every shard of every asset on this relay until guardians pick them
      # up. App ceilings: 100mb per asset x 10 guardians x ~10 assets
      # awaiting pickup = 10gb. Must stay >= max_file_size, or the largest
      # declarable file could never be declared (FileManager guards this at
      # boot). This caps a runaway single identity, not a determined
      # attacker (hpks are cheap to mint) — the global handshake ceiling is
      # that defense. nil or -1 for unlimited.
      max_storage_bytes: 10 * 1024 * 1024 * 1024, # 10Gb per sender hpk

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
      max_chunk_size: 500 * 1024, # 500kb default

      # Hard cap on the declared size of a single file upload, checked at
      # startFileUpload. nil disables the check.
      max_file_size: 2 * 1024 * 1024 * 1024, # 2Gb

      # Per-chunk byte allowance added on top of the declared file_size when
      # enforcing the upload size cap. per-chunk encryption overhead (like secretbox MAC)
      per_chunk_overhead: 128, # 128 bytes per chunk

      # Grace window: the cleanup job never prunes an on-disk chunk written more
      # recently than this, so an in-flight upload can't be deleted mid-flight.
      prune_grace: 1.hour.to_i,

      # Default: files expire after 7 days
      files_expiration: 7.days.seconds.to_i,

      # An upload that never completed stops holding quota and disk after
      # this long: the cleanup sweep deletes uploads whose status never
      # reached COMPLETE. Clients restart interrupted uploads from scratch
      # with a fresh uploadID, so a stalled upload is garbage that would
      # otherwise hold its declared bytes against the sender's quota for
      # the whole files_expiration. nil or -1 disables the sweep.
      stalled_upload_expiration: 1.day.seconds.to_i,
    }
    config.cache_store = :redis_cache_store, {
      url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" },
      expires_in: 10.minutes,
      # Size the cache pool to the Puma thread count (+2) so a busy thread
      # never blocks/times-out on a checkout → spurious 500. Mirrors
      # the data-Redis pool in config/initializers/redis.rb; default was 5 < 6.
      pool: { size: Integer(ENV.fetch("ZAX_THREADS", 6)) + 2, timeout: 5 }
    }

    # --- Relay default configuration END ---
  end
end
