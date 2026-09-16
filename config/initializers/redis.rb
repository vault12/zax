# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
#
=begin
The Ruby client establishes the connection to redis lazily
– ie, whenever it really needs it.
In this case, you're creating a new instance without issuing any
commands, and that's why you're not able to rescue the exception.

https://groups.google.com/forum/#!topic/redis-db/T7JzYqYEAqk
=end

require 'key_params'
require 'connection_pool'
include KeyParams

redis_options = {
  url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" },
  ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
}

# Test isolation: never run the suite against the app's db0 — a real
# relay may live there and the tests mutate/delete keys. Force a dedicated test
# db (default 15) regardless of the db in REDIS_URL. An explicit `db:` option
# overrides the URL's db. Set ZAX_TEST_DB to run parallel suites on distinct
# dbs (e.g. one on 15, another on 14) so they can't collide.
if Rails.env.test?
  test_db = Integer(ENV.fetch("ZAX_TEST_DB", 15))
  raise "ZAX test isolation: refusing to run tests against redis db 0 (set ZAX_TEST_DB)" if test_db.zero?
  redis_options[:db] = test_db
end

# One Redis connection PER THREAD via a pool. A single shared connection breaks
# WATCH/MULTI isolation: WATCH state is per-connection, so with every Puma thread
# on one socket another thread can clear the watch between WATCH and EXEC, letting
# EXEC commit without the optimistic lock (silent lost updates).
# Size the pool to at least the Puma thread count so a thread never blocks.
redis_pool_size = Integer(ENV.fetch("ZAX_THREADS", 6)) + 2

# Raw pool: use $redis_pool.with { |conn| ... } to hold ONE connection across a
# multi-command sequence (a WATCH/MULTI transaction). See runRedisTransaction.
$redis_pool = ConnectionPool.new(size: redis_pool_size, timeout: 5) { Redis.new(redis_options) }

# Drop-in handle for single, self-contained commands ($redis.get/set/...): the
# Wrapper checks a connection out of the pool per method call, which is safe for
# individual (already-atomic) commands but NOT for spanning a transaction.
$redis = ConnectionPool::Wrapper.new(pool: $redis_pool)

# Used by file manager to keep watch on files to be deleted later
$redis.persist ZAX_GLOBAL_FILES

# Used by session difficulty throttling
$redis.set ZAX_ORIGINAL_DIFF, Rails.configuration.x.relay.difficulty
$redis.persist ZAX_ORIGINAL_DIFF
