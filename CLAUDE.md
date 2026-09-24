# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Zax is a NaCl-based cryptographic relay: an ephemeral, in-memory "dead drop" for end-to-end encrypted messages and files between devices. It stores nothing it can decrypt and nothing in permanent storage (Redis with expiration timers, plus encrypted file chunks on disk). Full protocol spec: http://bit.ly/nacl_relay_spec. The client library is [Glow](https://github.com/vault12/glow.ts).

## Commands

Redis must be running locally (`redis-server`) for both the app and the tests — tests exit immediately if it's unreachable. Ruby 3.4 (see `.ruby-version`; rvm gemset `zax`).

```shell
bundle install                 # install gems
./install_dependencies.sh     # bundle + npm install, populates public/ from the zax-dashboard npm package

rails s -p 8080                # run the relay

rake test                      # full suite (CI runs `bundle exec rake`); add -v for verbose
SLOW=1 rake test               # also run slow wall-clock tests (sweep TTL lifecycle), skipped by default
rake test:controllers          # one group; also test:integration
rake test test/integration/command_test.rb   # single test file
```

Gemfile pin to preserve: `connection_pool < 3` — activesupport 7.2's `:redis_cache_store` breaks on boot with connection_pool 3.x.

## Architecture

Rails 7.2 API-only app with **no database** — ActiveRecord is disabled (`db/` is a stub). All state lives in Redis and, for file uploads, on disk under `shared/uploads/`. Two Redis connections: the `$redis` global (`config/initializers/redis.rb`, db 0) for mailbox/file data, and `Rails.cache` as `:redis_cache_store` (db 1) for session tokens and keys.

### Request protocol

Only four routes (`config/routes.rb`), all POST, all with plain-text bodies of `\r\n`-separated base64 lines whose exact byte sizes are fixed by constants in `lib/key_params.rb` (controllers `request.body.read` exactly that many bytes):

1. `/start_session` → `SessionController` — client sends a random token, relay responds with its token + a proof-of-work difficulty.
2. `/verify_session` → `SessionController` — client answers the PoW challenge, receives a temporary relay session public key.
3. `/prove` → `ProofController` — client proves ownership of its long-term key; the relay only ever stores the *hash* of the public key (`hpk`), which is the global address of a mailbox.
4. `/command` → `CommandController` — everything else. The body is NaCl-encrypted with session keys; `process_cmd` decrypts it, reads `data[:cmd]`, and dispatches to a command object.

### Command layer

`CommandController::ALL_COMMANDS` lists the ten commands. Each is a class in `app/services/commands/` extending `ZaxCommand` (`app/services/zax_command.rb`), constructed with `(hpk, mailbox)` and implementing `process(data)`. Messaging commands (`upload`, `count`, `download`, `delete`, `messageStatus`) go through `lib/mailbox.rb`; file commands (`startFileUpload`, `uploadFileChunk`, `downloadFileChunk`, `fileStatus`, `deleteFile`) extend `FileCmd` and go through `lib/file_manager.rb`.

- **Mailbox** (`lib/mailbox.rb`): Redis-hash-backed message store keyed by hpk (`mbx_<hpk>`, `msg_<hpk>_<nonce>`), with retried Redis transactions (`Helpers::TransactionHelper`).
- **FileManager** (`lib/file_manager.rb`): stores encrypted chunks as files whose names are derived from the client-visible `uploadID` plus a local `secret_seed.txt` — deleting that seed permanently orphans stored files. Has a `:test` mode that skips disk writes and serves random bytes.

`lib/` and `app/services/` are eager-loaded via `config.eager_load_paths` — plain Ruby, not autoloaded Rails conventions.

### Errors and helpers

Error handling is centralized: controllers wrap their work in `reportCommonErrors` (`app/controllers/application_controller.rb`), and protocol violations raise subclasses of `ZaxError` (`lib/errors/`) which respond via `http_fail` — failures return an empty body with an `X-Error-Details` header. Shared request-parsing/crypto helpers live in `lib/helpers/` and `lib/response_helper.rb` (`render_encrypted` for NaCl-boxed responses).

### Background jobs and tuning

- `DiffAdjustJob`: dynamically raises the PoW handshake difficulty under load (disabled unless `config.x.relay.period` is set).
- `FilesCleanupJob`: deletes expired/orphaned uploaded files.

All relay tuning (difficulty, expiration timers, file-store settings) lives in `config.x.relay.*` inside `config/application.rb`.

### Tests

Minitest with helpers in `test/test_helper.rb` that emulate the client side: `_setup_keys`/`_send_command` write session keys straight into `Rails.cache` and NaCl-encrypt command bodies, so integration tests exercise real crypto against a live Redis. Log output uses emoji/color prefixes defined in `lib/key_params.rb`.
