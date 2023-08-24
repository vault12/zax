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
      @fm.delete_file uploadID, 20
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
    for uploadID in @uids
      storage_name = @fm.storage_name_from_id @fm.storage_from_upload uploadID
      rds.srem(ZAX_GLOBAL_FILES, storage_tag(storage_name))
      rds.del(storage_tag(storage_name))
    end

    # Now files are fully orphaned from Redis. They will be pruned.
    FilesCleanupJob.perform_now

    for uploadID in @uids
      storage_name = @fm.storage_name_from_id @fm.storage_from_upload uploadID
      for part in (0...10) do
        assert_not File.exist? "#{@fm.storage_path}#{storage_name}.#{part}.bin"
      end
    end
  end

end
