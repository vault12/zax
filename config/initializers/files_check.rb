# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

# Kick the stale-file sweep once at boot: with no timestamp in
# Redis the process wins the SET NX election and sweeps immediately. Safe
# under Puma cluster preload — however many processes call this, exactly one
# wins the lock. No-op when config.x.relay.stale_file_check is nil (tests).
Rails.application.config.after_initialize do
  begin
    FilesCheck.maybe_run
  rescue StandardError => e
    Rails.logger.warn "FilesCheck boot trigger failed: #{e.message}"
  end
end
