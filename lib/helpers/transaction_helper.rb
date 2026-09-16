# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

require 'utils'
require 'errors/transaction_error'

module Helpers
  module TransactionHelper
    include Utils
    include Errors

    # Redis transaction is structured as following sequence
    #
    # WATCH key
    #   read any data, presumed from key or dependend on key
    # MULTI
    #   change data in key or depended on key
    # EXEC
    #   check EXEC result: atomic success or failure
    #
    # If any other thread changes data in key after WATCH key is issued
    # whole transaction will fail and needs to be rerun.
    #
    # We need two blocks: one optional to read key-dependent data and another
    # to write changes. runRedisTransaction uses one or two blocks, with read_proc
    # being optional handler to read data inside watch. The main block
    # is required and is executed between MULTI/EXEC
    #
    # CommandContoller / 'uploadFileChunk' shows an example of full Redis
    # transaction with protected read and write.
    #
    # test 'file commands: race conditions' triggers highly conflicted write
    # that is completed after number of failures recovered by while loop
    # in runRedisTransaction

    def runRedisTransaction(watch_key, hpk =nil, op = '', read_proc = nil)
      limit = Rails.configuration.x.relay.mailbox_retry
      count, res = 0, nil
      # watch_key may be a single key or an array of keys. WATCH them all so a
      # guarded read touching any of them re-evaluates (and can abort) whenever a
      # concurrent write changes it — this is what makes the caller's pre-write
      # checks atomic with the write.
      watch_keys = Array(watch_key).compact
      label = hpk ? "mailbox #{dumpHex(hpk.from_b64)}," : "key #{watch_keys.join(',')}"

      # Hold ONE pooled connection for the entire WATCH/read/MULTI/EXEC sequence
      # and expose it as this thread's `rds`, so the guarded read and the write
      # run on the same connection no other thread can touch — the optimistic
      # lock is honoured. Reuse an already-checked-out connection if a
      # transaction is somehow nested, to avoid pool starvation.
      run = lambda do |conn|
        while count < limit and res.nil?
          conn.watch(*watch_keys) unless watch_keys.empty?
          read_data = read_proc.call() if read_proc
          res = conn.multi do |transaction|
            yield(read_data, transaction)
          end

          if res.nil?
            count += 1
            sleep 0.1 + rand() * 0.1 # let other mbx writes complete
            logger.warn "#{INFO_NEG} #{label} : retry #{op}, #{count}/#{limit}"
          end
          logger.info "#{INFO_GOOD} #{label}, #{op} success, after #{count} retry" if res and count>0
        end
      end

      if Thread.current[:zax_redis]
        run.call(Thread.current[:zax_redis])
      else
        $redis_pool.with do |conn|
          Thread.current[:zax_redis] = conn
          begin
            run.call(conn)
          ensure
            # Clear any dangling WATCH before the connection returns to the pool,
            # so a later checkout by another thread can't inherit it.
            conn.unwatch rescue nil
            Thread.current[:zax_redis] = nil
          end
        end
      end

      if count >= limit and res.nil?
        raise TransactionError.new(self, {
          hpk: hpk,
          msg: "Redis transaction helper: #{op} in #{label} failure after #{count} retries"
          })
      end
      return res
    end

    # Redis handle for the current thread. Inside a runRedisTransaction the thread
    # holds one pooled connection (so WATCH/read/MULTI share it); otherwise this is
    # the pool wrapper, which checks a connection out per individual command.
    def rds
      Thread.current[:zax_redis] || $redis
    end
  end
end
