# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class FilesCleanupJobTest < ActiveJob::TestCase

  def storage_tag(storage_name)
    "#{STORAGE_PREFIX}#{storage_name}"
  end

  setup do
    @fm = FileManager.new
    @uids = ["1","2","3"]
    for uploadID in @uids
      for part in (0...(10+rand(10)))
        @fm.save_data uploadID, "hello world", part
      end
    end
  end

  teardown do
    for uploadID in @uids
      @fm.delete_file uploadID
    end
  end

  test "keep whitelist files" do
    for uploadID in @uids
      storage_name = @fm.storage_name_from_id @fm.storage_from_upload uploadID
      rds.sadd(ZAX_GLOBAL_FILES, storage_tag(storage_name))
      rds.set(storage_tag(storage_name), 1)
      rds.expire(storage_tag(storage_name), 1)
    end

    # all files are whitelisted and should stay up
    FilesCleanupJob.perform_now

    for uploadID in @uids
      storage_name = @fm.storage_name_from_id @fm.storage_from_upload uploadID
      for part in (0...10) do
        assert File.exist? "#{@fm.storage_path}#{storage_name}.#{part}.bin"
      end
    end
  end

  test "delete expired files" do
    for uploadID in @uids
      storage_name = @fm.storage_name_from_id @fm.storage_from_upload uploadID
      rds.sadd(ZAX_GLOBAL_FILES, storage_tag(storage_name))
    end

    # Files are now only in global list, and will be deleted as expired
    FilesCleanupJob.perform_now

    for uploadID in @uids
      storage_name = @fm.storage_name_from_id @fm.storage_from_upload uploadID
      for part in (0...10) do
        assert_not File.exist? "#{@fm.storage_path}#{storage_name}.#{part}.bin"
      end
    end
  end

  test "prune orphan files" do
    old = Time.now - @fm.prune_grace - 60
    for uploadID in @uids
      storage_name = @fm.storage_name_from_id @fm.storage_from_upload uploadID
      rds.srem(ZAX_GLOBAL_FILES, storage_tag(storage_name))
      rds.del(storage_tag(storage_name))
      # Real orphans are old; age them past the grace so they're eligible.
      Dir["#{@fm.storage_path}#{storage_name}.*.bin"].each { |f| File.utime(old, old, f) }
    end

    # Now files are fully orphaned from Redis and past the grace. They are pruned.
    FilesCleanupJob.perform_now

    for uploadID in @uids
      storage_name = @fm.storage_name_from_id @fm.storage_from_upload uploadID
      for part in (0...10) do
        assert_not File.exist? "#{@fm.storage_path}#{storage_name}.#{part}.bin"
      end
    end
  end

  # a chunk written while the cleanup job runs (fresh mtime, and for a
  # brief window not yet reflected in the tracked set) must NOT be pruned. The
  # mtime grace guarantees a freshly-written file is always spared.
  test "grace protects freshly written orphan files" do
    for uploadID in @uids
      storage_name = @fm.storage_name_from_id @fm.storage_from_upload uploadID
      rds.srem(ZAX_GLOBAL_FILES, storage_tag(storage_name))
      rds.del(storage_tag(storage_name))
    end

    # Files are seconds old (written in setup) => within prune_grace.
    FilesCleanupJob.perform_now

    for uploadID in @uids
      storage_name = @fm.storage_name_from_id @fm.storage_from_upload uploadID
      for part in (0...10) do
        assert File.exist?("#{@fm.storage_path}#{storage_name}.#{part}.bin"),
          'freshly-written orphan chunk must survive the prune grace'
      end
    end
  end

  # deleteFile must remove chunks stored at ANY part index, not just 0..count-1.
  # `parts` an index-keyed list, so total_chunks is a COUNT decoupled from the indices
  test "delete_file removes chunks at sparse part indices" do
    uploadID = "sparse-#{SecureRandom.hex(6)}"
    storage_name = @fm.storage_name_from_id @fm.storage_from_upload uploadID
    indices = [0, 5, 299] # non-contiguous; count (3) != the actual indices
    indices.each { |part| @fm.save_data uploadID, "cipher", part }
    indices.each do |part|
      assert File.exist?("#{@fm.storage_path}#{storage_name}.#{part}.bin"), "chunk #{part} written"
    end

    @fm.delete_file uploadID

    indices.each do |part|
      assert_not File.exist?("#{@fm.storage_path}#{storage_name}.#{part}.bin"),
        "chunk #{part} deleted (the old 0...count loop would have missed 5 and 299)"
    end
  ensure
    @fm._delete_chunks storage_name, 'test-cleanup' if storage_name # belt-and-suspenders
  end

end
