# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'
require 'mailbox'

class MailboxExpireTest < ActionDispatch::IntegrationTest
  include Helpers::TransactionHelper

  test 'expiring messages' do
    @debug = false
    @config = getConfig
    setHpks
    for i in 0..10
      puts i if @debug
      expireIterate
    end
    cleanup
  end

  private

  def expireIterate
    uploadMessages
    countMessages
    downloadMessages
    countMessages
  end

  def uploadMessages
    for i in 0..@config[:upload_number_of_messages]
      uploadMessage
    end
  end

  def uploadMessage
    ary = getHpks
    pairary = _get_random_pair(@config[:number_of_mailboxes] - 1)
    hpk_b64 = ary[pairary[0]]
    from = ary[pairary[1]].from_b64

    options = {}
    options[:mbx_expire] = 20.seconds.to_i
    options[:msg_expire] = Random.new.rand(10..15)

    mbx = Mailbox.new hpk_b64, options
    assert_not_nil mbx.hpk
    nonce = h2(rand_bytes(16))
    mbx.store from, nonce, "hello from #{ary[pairary[1]]}"
    rds.incrby(@config[:total_number_of_messages], 1)
  end

  # compare the actual number of messages in the redis mailbox
  # against a running total of the messages as they get
  # uploaded and downloaded
  def countMessages
    total = 0
    ary = getHpks
    ary.each do |hpk|
      mbx = Mailbox.new hpk
      count = mbx.count
      total += count
    end
    total_redis = rds.get(@config[:total_number_of_messages])
    _print_debug 'total mbx count = ', total if @debug
    _print_debug 'total redis key = ', total_redis if @debug
    # turn on manually when changing mailbox code
    # assert_equal(total.to_s,total_redis)
  end

  # download the messages and then delete them
  def downloadMessages
    ary = getHpks
    total = 0
    ary.each do |hpk|
      mbx = Mailbox.new hpk
      download = mbx.read_all
      total += download.length
      deleteMessages(mbx, download)
    end
  end

  # delete half of the total number of messages
  def deleteMessages(mbx, messages)
    halfdelete = _getHalfOfNumber(messages.length)
    half = halfdelete - 1
    0.upto(half) do |i|
      nonce = b64enc messages[i][:nonce]
      value = mbx.delete(nonce)
      rds.decrby(@config[:total_number_of_messages], 1)
    end
  end

  def checkClean
    ary = getHpks
    ary.each do |hpk|
      result_mbx = rds.exists?("mbx_#{hpk}")
      assert_equal(result_mbx, false)
      result_msg = rds.keys("msg_#{hpk}_*")
      assert_equal(result_msg, [])
    end
    rds.del(@config[:hpkey])
  end

  # delete and cleanup keys from Redis
  def cleanup
    ary = getHpks
    ary.each do |hpk|
      result_mbx = rds.exists?("mbx_#{hpk}")
      rds.del("mbx_#{hpk}")
      msg_keys = rds.keys("msg_#{hpk}_*")
      msg_keys.each do |key|
        rds.del(key) if rds.exists?(key)
      end
    end
    rds.del(@config[:hpkey])
    rds.del(@config[:total_number_of_messages])
  end

  # Establish an HPK as a function of a string
  # and the number of the mailbox
  def setHpks
    for i in 0..@config[:number_of_mailboxes] - 1
      hpk = h2('vault12.com_' + i.to_s)
      hpk_b64 = b64enc hpk
      rds.sadd(@config[:hpkey], hpk_b64)
    end
  end

  # get an array of HPKs from a Redis set
  def getHpks
    result = rds.smembers(@config[:hpkey])
  end

  def _getHalfOfNumber(calchalf)
    half = calchalf.to_f / 2
    half = half.to_i
  end

  # this is the way you configure the test
  def getConfig
    config = {
      number_of_mailboxes: 3,
      upload_number_of_messages: 24,
      hpkey: 'hpksdelete',
      total_number_of_messages: 'hpktotalmessages'
    }
  end

  def _print_debug(msg, value)
    print "#{msg} = #{value}"; puts
  end

end
