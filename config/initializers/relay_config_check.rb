# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

# The single-use verify slot (session_timeout) must live at least as long as
# the handshake record (token_timeout): if the slot could expire while the
# handshake record is still valid, the single-use guarantee would weaken to
# single-write. The shipped values hold a 20x margin (1 minute vs 20
# minutes); refuse to boot on an inverted override instead of silently
# accepting it, mirroring the max_storage_bytes/max_file_size boot check.
tt = Rails.configuration.x.relay.token_timeout
st = Rails.configuration.x.relay.session_timeout
if tt and st and st < tt
  raise "relay config: session_timeout (#{st}) must be >= token_timeout (#{tt})"
end
