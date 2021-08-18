class FilesCleanupJob < ApplicationJob
  queue_as :default

  def perform(*args)
    return unless FileManager.is_enabled?

    FileManager.new.delete_expired_all
  end
end
