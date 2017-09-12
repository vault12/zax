class FilesCleanupJob < ApplicationJob
  queue_as :default

  def perform(*args)
    return unless FileManager.is_enabled?
    fm = FileManager.new
    fm.delete_expired_all
  end
end
