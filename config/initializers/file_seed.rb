# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

# Establish the file-storage secret_seed ONCE at boot. Under Puma
# preload_app! this runs in the master before workers fork, so every worker
# inherits the same in-memory seed and the persisted secret_seed.txt already
# exists — eliminating the fresh-deploy race where concurrent workers each
# generated a different seed. Without preload, each worker still converges via
# the atomic hard-link publish in FileManager#_establish_seed_file.
#
# A secret_seed ConfigError (too short, or sources disagreeing) is FATAL — the
# relay refuses to boot. Other transient errors are logged, not fatal, so a
# non-seed hiccup doesn't take down messaging (which needs no file store).
Rails.application.config.after_initialize do
  begin
    FileManager.new if FileManager.is_enabled?
  rescue Errors::ConfigError => e
    # A misconfigured secret_seed (too short, or config/ENV/file disagree) is
    # unrecoverable: stored files are bound to exactly one seed and we must not
    # guess. Refuse to boot and let the admin reconcile it.
    Rails.logger.fatal "FileManager: refusing to start — #{e.msg}"
    raise
  rescue StandardError => e
    # Transient failures (e.g. a not-yet-writable uploads dir on first boot)
    # are logged; the first file command re-attempts establishment.
    Rails.logger.error "FileManager seed establishment at boot failed: #{e.message}"
  end
end
