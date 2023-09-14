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
      label = hpk ? "mailbox #{dumpHex(hpk.from_b64)}," : "key #{watch_key}"

      while count < limit and res.nil?
        rds.watch watch_key if watch_key
        read_data = read_proc.call() if read_proc
        res = rds.multi do |transaction|
          yield(read_data, transaction)
        end

        if res.nil?
          count += 1
          sleep 0.1 + rand() * 0.1 # let other mbx writes complete
          logger.warn "#{INFO_NEG} #{label} : retry #{op}, #{count}/#{limit}"
        end
        logger.info "#{INFO_GOOD} #{label}, #{op} success, after #{count} retry" if res and count>0
      end
      if count >= limit and res.nil?
        raise TransactionError.new(self, {
          hpk: hpk,
          msg: "Redis transaction helper: #{op} in #{label} failure after #{count} retries"
          })
      end
      return res
    end

    # Every web worker thread gets its own Redis connection,
    # so any multithreading conflicts are resolved by Redis transactions
    def rds
      $redis
    end
  end
end
