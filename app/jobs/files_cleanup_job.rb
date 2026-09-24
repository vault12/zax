# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class FilesCleanupJob < ApplicationJob
  queue_as :default

  def perform(*args)
    return unless FileManager.is_enabled?

    fm = FileManager.new
    fm.delete_stalled_uploads
    fm.delete_expired_all

    # Stamp the sweep timestamp and release the election lock so the next sweep is scheduled stale_file_check from now 
    FilesCheck.record_completed
  end
end