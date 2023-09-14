# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'
require 'prove_test_helper'

class MailboxDeleteTest < ProveTestHelper
  test 'upload messages to mailbox for delete' do
    # This whole test should be rewritten - wrong overall apporach to testing
    # HACK

    # configure your test
    @config = getConfig

    # Use the ProveTestHelper to set your HPKs
    setHpks

    # Upload your messages
    for i in 0..@config[:upload_number_of_messages]
      uploadMessage
    end

    increment_number_of_messages
    # After the upload, get the number of messages before deleting them
    numofmessages_before = get_number_of_messages

    # Build a hash of all of the hpk mailboxes
    mbx_hash_before = get_mbx_hash

    # After uploading the messages, test the download command
    hpk, messages = downloadMessages

    # Now go ahead and delete the messages you downloaded
    numofmessages_delete = deleteMessages(hpk, messages)

    decrement_number_of_messages(numofmessages_delete)
    # check to make sure you deleted the correct number of messages
    numofmessages_after = get_number_of_messages

    # Build a hash of all of the hpk mailboxes after the delete
    mbx_hash_after = get_mbx_hash

    # Compare the 2 hashes: one before the delete and one after the delete
    _compare_mbx_hash(mbx_hash_before, mbx_hash_after, hpk, numofmessages_delete)

    # assert the number of messages after delete =
    # number of messages before delete - number of messages deleted
    assert_equal(numofmessages_after.to_i, numofmessages_before.to_i - numofmessages_delete)

    # cleanup all of the redis keys and then end
    cleanup
  end

  private

  def uploadMessage
    ary = getHpks
    # see the readme in this directory for more details on _get_random_pair
    pairary = _get_random_pair(@config[:number_of_mailboxes] - 1)
    hpk = ary[pairary[0]].from_b64
    to_hpk = ary[pairary[1]]
    data = { cmd: 'upload', to: to_hpk, payload: 'hello world 0' }
    n = _make_nonce
    @session_key = Rails.cache.read("session_key_#{hpk}")
    @client_key = Rails.cache.read("client_key_#{hpk}")
    skpk = @session_key.public_key
    skpk = b64enc skpk
    ckpk = b64enc @client_key
    _post '/command', hpk, n, _client_encrypt_data(n, data)
  end

  # this tests the download command in the CommandController
  def downloadMessages
    ary = getHpks
    pairary = _get_random_pair(@config[:number_of_mailboxes] - 1)
    hpk = ary[pairary[0]].from_b64
    to_hpk = ary[pairary[1]]
    data = { cmd: 'download' }
    n = _make_nonce
    @session_key = Rails.cache.read("session_key_#{hpk}")
    @client_key = Rails.cache.read("client_key_#{hpk}")
    skpk = @session_key.public_key
    skpk = b64enc skpk
    ckpk = b64enc @client_key
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response

    # done posting the download command and getting back the messages
    # now lets check and make sure we got the correct number of messages
    lines = _check_response(response.body)
    assert_equal(2, lines.length)
    rn = lines[0].from_b64
    rct = lines[1].from_b64
    data = _client_decrypt_data rn, rct
    mbxcount = countMessage(hpk)
    mbxcount = MAX_ITEMS if mbxcount >= MAX_ITEMS
    assert_not_nil data
    assert_equal data.length, mbxcount
    [hpk, data]
  end

  def deleteMessages(hpk, msgin)
    halfdelete = _getHalfOfNumber(msgin.length)
    half = halfdelete - 1
    0.upto(half) do |i|
      nonce = msgin[i][:nonce]
      deleteMessage(hpk, nonce)
    end
    halfdelete
  end

  def countMessage(hpk)
    @session_key = Rails.cache.read("session_key_#{hpk}")
    @client_key = Rails.cache.read("client_key_#{hpk}")
    data = { cmd: 'count' }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response
    lines = _check_response(response.body)
    assert_equal(2, lines.length)
    rn = lines[0].from_b64
    rct = lines[1].from_b64
    count = _client_decrypt_data rn, rct
    assert_not_nil count
    count
  end

  def deleteMessage(hpk, nonce)
    @session_key = Rails.cache.read("session_key_#{hpk}")
    @client_key = Rails.cache.read("client_key_#{hpk}")
    arydelete = []
    arydelete.push(nonce)
    data = { cmd: 'delete', payload: arydelete }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    _success_response
    c = response.body.to_i
    assert_in_delta 10,c,10
  end

  def increment_number_of_messages
    numofmessages = @config[:upload_number_of_messages] + 1
    rds.incrby(@config[:total_number_of_messages], numofmessages)
  end

  def decrement_number_of_messages(numofmessages)
    rds.decrby(@config[:total_number_of_messages], numofmessages.to_s)
  end

  def get_number_of_messages
    numofmessages = rds.get(@config[:total_number_of_messages])
    numofmessages_mbx = get_total_number_of_messages_across_mbx
    assert_equal(numofmessages.to_i, numofmessages_mbx)
    numofmessages
  end

  # this gets the total number of messages across all mailboxes
  def get_total_number_of_messages_across_mbx
    ary = getHpks
    total_messages = 0
    ary.each do |key|
      mbxkey = 'mbx_' + key
      num_of_messages = rds.hlen(mbxkey)  # HACK: uses impl specifics
      total_messages += num_of_messages.to_i
    end
    total_messages
  end

  # this builds a hash of all of the hpk mailboxes
  def get_mbx_hash
    mbx_hash = {}
    ary = getHpks
    ary.each do |key|
      mbxkey = 'mbx_' + key
      num_of_messages = rds.hlen(mbxkey)   # HACK: uses impl specifics
      mbx_hash[mbxkey] = num_of_messages.to_i
    end
    mbx_hash
  end

  def setHpks
    cleanup
    for i in 0..@config[:number_of_mailboxes] - 1
      hpk = setup_prove
      hpk_b64 = b64enc hpk
      rds.sadd(@config[:hpkey], hpk_b64)
    end
  end

  ### check to see if there are hpks in hpkdb
  def getHpks
    rds.smembers(@config[:hpkey])
  end

  def getConfig
    config = {
      number_of_mailboxes: 3,
      upload_number_of_messages: 24,
      hpkey: 'hpksdelete',
      total_number_of_messages: 'hpktotalmessages'
    }
  end

  def _check_response(body)
    fail BodyError.new self, msg: 'No request body' if body.nil?
    nl = body.include?("\r\n") ? "\r\n" : "\n"
    body.split nl
  end

  def _getHalfOfNumber(calchalf)
    half = calchalf.to_f / 2
    half = half.to_i
  end

  def _compare_mbx_hash(mbx_hash_before, mbx_hash_after, hpk, numofmessages_delete)
    hpk = hpk.to_b64
    mbxkey = 'mbx_' + hpk
    mbx_hash_before.each do |key, value_before|
      value_after = mbx_hash_after[key]
      if key == mbxkey
        assert_equal(value_before - numofmessages_delete, value_after)
        assert_not_equal(value_before, value_after) if numofmessages_delete != 0
      else
        assert_equal(value_before, value_after)
      end
    end
  end

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
    rds.del(@config[:hpkey].to_s)
    rds.del(@config[:number_of_iterations].to_s)
    rds.del(@config[:total_number_of_messages].to_s)
  end
end
