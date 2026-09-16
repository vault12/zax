# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

# End-to-end expiry lifecycle of the stale-file sweep:
# files tracked with a real Redis TTL must be bypassed by every sweep that
# runs before the TTL elapses and fully removed by the first sweep after.
# prune_grace is zeroed for the group so ONLY the expiration logic decides —
# no chunk survives because of its mtime.
class FilesSweepExpirationTest < ActiveSupport::TestCase

  EXPIRE = 4 # seconds; sweeps run at ~0 and ~T/2 (live) and past TTL (expired)

  setup do
    # ~11s of unavoidable wall-clock sleeps (real Redis TTLs), so this group
    # is excluded from the default suite. Activate with:  SLOW=1 rake test
    skip 'slow lifecycle test: set SLOW=1 to run' unless ENV['SLOW']

    @save_grace = Rails.configuration.x.relay.file_store[:prune_grace]
    Rails.configuration.x.relay.file_store[:prune_grace] = 0
    @fm = FileManager.new
    @uids = []
    @chunks = {}
  end

  teardown do
    next unless @uids # skipped before setup state was built
    Rails.configuration.x.relay.file_store[:prune_grace] = @save_grace
    @uids.each do |uid|
      _chunk_files(uid).each do |f|
        File.delete f
      rescue Errno::ENOENT
        next
      end
      $redis.srem ZAX_GLOBAL_FILES, _tag(uid)
      $redis.del _tag(uid)
    end
  end

  test 'sweep honors tracking-key expiration through the full lifecycle' do
    10.times { _store_tracked_file rand_bytes(32), EXPIRE }

    # t≈0: nothing expired yet — the sweep must not touch a single chunk
    FilesCleanupJob.perform_now
    @uids.each do |uid|
      assert_equal @chunks[uid], _chunk_files(uid).length, 'fresh file lost chunks'
      assert $redis.sismember(ZAX_GLOBAL_FILES, _tag(uid)), 'fresh file dropped from tracked set'
    end

    # t≈TTL/2: still live — again no change
    sleep EXPIRE / 2.0
    FilesCleanupJob.perform_now
    @uids.each do |uid|
      assert_equal @chunks[uid], _chunk_files(uid).length, 'live file lost chunks mid-TTL'
    end

    # past TTL: every chunk of every file is gone and the set is reconciled
    sleep EXPIRE / 2.0 + 1.5
    FilesCleanupJob.perform_now
    @uids.each do |uid|
      assert_empty _chunk_files(uid), 'expired file still on disk'
      assert_not $redis.sismember(ZAX_GLOBAL_FILES, _tag(uid)), 'expired file still in tracked set'
    end
  end

  test 'sweep deletes only expired files and bypasses live ones' do
    5.times { _store_tracked_file rand_bytes(32), EXPIRE }
    expired = @uids.dup
    5.times { _store_tracked_file rand_bytes(32), 300 } # far-future TTL: stays live
    live = @uids - expired

    sleep EXPIRE + 1.5
    FilesCleanupJob.perform_now

    expired.each { |uid| assert_empty _chunk_files(uid), 'expired file still on disk' }
    live.each do |uid|
      assert_equal @chunks[uid], _chunk_files(uid).length, 'live file swept alongside expired ones'
      assert $redis.sismember(ZAX_GLOBAL_FILES, _tag(uid)), 'live file dropped from tracked set'
    end
  end

  private

  # Store a file the way a real upload lands: chunks on disk plus a tracking
  # key (with TTL) and a tracked-set membership, as save_file_tracking_info does
  def _store_tracked_file(uid, ttl)
    parts = 2 + rand(4) # 2..5 chunks, randomized between runs
    parts.times { |p| @fm.save_data uid, "chunk data #{p}", p }
    $redis.sadd ZAX_GLOBAL_FILES, _tag(uid)
    $redis.set _tag(uid), 1, ex: ttl
    @uids << uid
    @chunks[uid] = parts
  end

  def _tag(uid)
    "#{STORAGE_PREFIX}#{@fm.storage_name_from_id(@fm.storage_from_upload(uid))}"
  end

  def _chunk_files(uid)
    name = @fm.storage_name_from_id @fm.storage_from_upload(uid)
    Dir["#{@fm.storage_path}#{name}.*.bin"]
  end

end
