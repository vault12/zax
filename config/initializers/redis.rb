=begin
The Ruby client establishes the connection to redis lazily
– ie, whenever it really needs it.
In this case, you're creating a new instance without issuing any
commands, and that's why you're not able to rescue the exception.

https://groups.google.com/forum/#!topic/redis-db/T7JzYqYEAqk
=end

REDISCFG = {
 'host' => 'localhost',
 'port' => 6379
}

Redis.current = Redis.new :host => REDISCFG['host'],
                          :port => REDISCFG['port']
