# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class FilesCleanupJob < ApplicationJob
  queue_as :default

  def perform(*args)
    return unless FileManager.is_enabled?
    fm = FileManager.new
    fm.delete_expired_all
  end
end
