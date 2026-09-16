# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

# Traffic-driven scheduler for the stale-file sweep. Nothing is
# ever scheduled into the future — the durability problem of the in-process
# :async job executor disappears because a sweep lost to a restart is simply
# re-triggered by the next request.
#
# Three tiers, each strictly cheaper than the next:
#   1. per-process memory  — one integer compare, what almost every request hits
#   2. Redis timestamp     — one GET; re-arms memory after a worker restart or
#                            when another worker already swept
#   3. SET NX election     — sweep is due; exactly one winner across all Puma
#                            workers/threads enqueues the job
#
# FilesCleanupJob calls record_completed on success, which stamps Redis and
# releases the lock. A crashed sweep self-heals: the lock TTL expires and the
# next request re-runs the election.
module FilesCheck
  LOCK_TTL = 10 * 60 # bounds a crashed sweep; sweeps take seconds

  class << self
    # Called on every request (ApplicationController) and once at boot
    def maybe_run
      period = Rails.configuration.x.relay.stale_file_check
      return unless period and FileManager.is_enabled?

      now = Time.now.to_i
      return if @last_check and now - @last_check < period

      ts = $redis.get(KeyParams::ZAX_FILES_CHECK_TS).to_i
      if ts > 0 and now - ts < period
        @last_check = ts
        return
      end
      run_async
    end

    # Cross-worker election: only the SET NX winner enqueues the sweep
    def run_async
      return unless $redis.set(KeyParams::ZAX_FILES_CHECK_LOCK, 1, nx: true, ex: LOCK_TTL)
      logger.info "#{KeyParams::INFO} FilesCheck: stale-file sweep is due, enqueueing FilesCleanupJob"
      FilesCleanupJob.perform_later
      true
    end

    # Called by FilesCleanupJob after a successful sweep
    def record_completed
      @last_check = Time.now.to_i
      $redis.set(KeyParams::ZAX_FILES_CHECK_TS, @last_check)
      $redis.del(KeyParams::ZAX_FILES_CHECK_LOCK)
    end

    # Forget the in-process cache (tests simulate a worker restart with this)
    def reset_memory!
      @last_check = nil
    end

    def logger
      Rails.logger
    end
  end
end
