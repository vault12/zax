# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'
require 'mailbox'

class MailboxBasicTest < ActionDispatch::IntegrationTest
  test 'basic functionality upload count download delete' do
    @config = getConfig
    setHpks
    for i in 0..@config[:upload_number_of_messages]
      uploadMessage
      countMessages
      downloadMessages
    end
    checkClean
  end

  private

  def uploadMessage
    ary = getHpks
    # see the readme in this directory for more details on _get_random_pair
    pairary = _get_random_pair(@config[:number_of_mailboxes] - 1)
    hpk = b64dec ary[pairary[0]]
    from = b64dec ary[pairary[1]]

    options = {}
    options[:mbx_expire] = 20.seconds.to_i
    options[:msg_expire] = 10.seconds.to_i

    mbx = Mailbox.new hpk, options
    assert_not_nil mbx.hpk
    nonce = h2(rand_bytes(16))
    mbx.store from, nonce, "hello from #{ary[pairary[1]]}"
  end

  def countMessages
    ary = getHpks
    ary.each do |hpk|
      hpk = b64dec hpk
      mbx = Mailbox.new hpk
    end
  end

  def downloadMessages
    ary = getHpks
    total = 0
    ary.each do |hpk|
      hpk = b64dec hpk
      mbx = Mailbox.new hpk
      download = mbx.read_all
      total += download.length
      deleteMessages(mbx, download)
    end
  end

  def deleteMessages(mbx, download_ary)
    download_ary.each do |msg|
      nonce = b64enc msg[:nonce]
      value = mbx.delete(nonce)
    end
  end

  def checkClean
    rds.del(@config[:hpkey])
  end

  def setHpks
    for i in 0..@config[:number_of_mailboxes] - 1
      hpk = h2('vault12.com_' + i.to_s)
      hpk_b64 = b64enc hpk
      rds.sadd(@config[:hpkey], hpk_b64)
    end
  end

  def getHpks
    result = rds.smembers(@config[:hpkey])
  end

  def getConfig
    config = {
      number_of_mailboxes: 3,
      upload_number_of_messages: 24,
      hpkey: 'hpksdelete'
    }
  end

  def rds
    Redis.current
  end
end
