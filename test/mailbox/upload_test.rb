# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'
require 'prove_test_helper'

class MailboxUploadTest < ProveTestHelper
  test 'upload messages to mailbox' do
    @config = getConfig
    setHpks
    for i in 0..@config[:number_of_messages]
      uploadMessage
    end
    check_number_of_messages
    cleanup
  end

  private

  def uploadMessage
    ary = getHpks
    pairary = _get_random_pair(@config[:number_of_mailboxes] - 1)
    hpk = ary[pairary[0]].from_b64
    to_hpk = ary[pairary[1]]
    data = { cmd: 'upload', to: to_hpk, payload: 'hello world 0' }
    n = _make_nonce
    @session_key = Rails.cache.read("session_key_#{hpk}")
    @client_key = Rails.cache.read("client_key_#{hpk}")

    skpk = @session_key.public_key
    skpk = b64enc skpk
    ckpk = @client_key.to_b64

    _post '/command', hpk, n, _client_encrypt_data(n, data)
  end

  # after all of the messages have been uploaded
  # check to make sure the number of messages is correct
  def check_number_of_messages
    iterations = rds.get(@config[:number_of_iterations]).to_i
    if iterations.nil?
      rds.set(@config[:number_of_iterations], 1)
      iterations = 1
    else
      iterations = iterations.to_i + 1
      rds.set(@config[:number_of_iterations], iterations)
    end
    total_messages = get_total_number_of_messages
    numofmessages = @config[:number_of_messages] + 1
    total_messages_calc = iterations * numofmessages
    assert_equal(total_messages, total_messages_calc)
  end

  # this gets the total number of messages across all mailboxes
  def get_total_number_of_messages
    ary = getHpks
    total_messages = 0
    ary.each do |key|
      mbxkey = 'mbx_' + key
      num_of_messages = rds.hlen(mbxkey)
      total_messages += num_of_messages.to_i
    end
    total_messages
  end

  # Calls the ProveTestHelper to get back an HPK
  # which is then stored for future calls to getHpks
  def setHpks
    cleanup
    for i in 0..@config[:number_of_mailboxes] - 1
      hpk = setup_prove
      rds.sadd(@config[:hpkey], hpk.to_b64)
    end
  end

  # get an array of HPKs from a Redis set
  def getHpks
    rds.smembers(@config[:hpkey])
  end

  # this is the way you configure the test
  def getConfig
    config = {
      number_of_mailboxes: 3,
      number_of_messages: 24,
      hpkey: 'hpksupload',
      number_of_iterations: 'hpkiteration'
    }
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
    rds.del(@config[:number_of_iterations])
  end

end
