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
include KeyParams

$redis = Redis.new(
  url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" },
  ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
)

# Used by file manager to keep watch on files to be deleted later
$redis.persist ZAX_GLOBAL_FILES

# Used by session difficulty throttling
$redis.set ZAX_ORIGINAL_DIFF, Rails.configuration.x.relay.difficulty
$redis.persist ZAX_ORIGINAL_DIFF
