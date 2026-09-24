# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

# traffic-driven stale-file sweep scheduling (lib/files_check.rb)
class FilesCheckTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  PERIOD = 3600

  setup do
    @save = Rails.configuration.x.relay.stale_file_check
    Rails.configuration.x.relay.stale_file_check = PERIOD
    FilesCheck.reset_memory!
    $redis.del KeyParams::ZAX_FILES_CHECK_TS, KeyParams::ZAX_FILES_CHECK_LOCK
  end

  teardown do
    Rails.configuration.x.relay.stale_file_check = @save
    FilesCheck.reset_memory!
    $redis.del KeyParams::ZAX_FILES_CHECK_TS, KeyParams::ZAX_FILES_CHECK_LOCK
  end

  test 'no timestamp anywhere: sweep runs immediately (boot case)' do
    assert_enqueued_with(job: FilesCleanupJob) { FilesCheck.maybe_run }
    # The winner still holds the election lock — no double-enqueue
    assert_no_enqueued_jobs { FilesCheck.maybe_run }
  end

  test 'completed sweep stamps redis, releases lock, arms memory' do
    perform_enqueued_jobs { FilesCheck.maybe_run }
    assert_operator $redis.get(KeyParams::ZAX_FILES_CHECK_TS).to_i, :>, 0
    assert_nil $redis.get(KeyParams::ZAX_FILES_CHECK_LOCK)
    # Tier 1: in-memory timestamp keeps subsequent requests quiet
    assert_no_enqueued_jobs { FilesCheck.maybe_run }
  end

  test 'worker restart re-arms from redis without a new sweep' do
    perform_enqueued_jobs { FilesCheck.maybe_run }
    FilesCheck.reset_memory! # fresh worker: empty memory, fresh redis stamp
    assert_no_enqueued_jobs { FilesCheck.maybe_run }
  end

  test 'stale timestamp triggers exactly one sweep across workers' do
    $redis.set KeyParams::ZAX_FILES_CHECK_TS, Time.now.to_i - PERIOD - 10
    assert_enqueued_jobs(1) do
      FilesCheck.maybe_run       # this worker wins the election
      FilesCheck.reset_memory!
      FilesCheck.maybe_run       # a "second worker" sees the lock, stands down
    end
  end

  test 'election lock held elsewhere: no enqueue' do
    $redis.set KeyParams::ZAX_FILES_CHECK_LOCK, 1, ex: 60
    assert_no_enqueued_jobs { FilesCheck.maybe_run }
  end

  test 'nil interval disables the trigger' do
    Rails.configuration.x.relay.stale_file_check = nil
    assert_no_enqueued_jobs { FilesCheck.maybe_run }
  end

end
