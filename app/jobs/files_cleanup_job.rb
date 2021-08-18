# frozen_string_literal: true

class FilesCleanupJob < ApplicationJob
  queue_as :default

  def perform(*_args)
    return unless FileManager.is_enabled?

    FileManager.new.delete_expired_all
  end
end
