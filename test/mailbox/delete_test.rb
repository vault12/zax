require 'test_helper'
require 'prove_test_helper'

class MailboxDeleteTest < ProveTestHelper

  test "upload messages to mailbox for delete" do
    @config = getConfig
    @tmout = Rails.configuration.x.relay.session_timeout - 5
    ary = getHpks
    setHpks if ary.length == 0
    for i in 0..@config[:upload_number_of_messages]
      uploadMessage
    end
    increment_number_of_messages
    print 'number of messages = ',get_number_of_messages; puts
    downloadMessage
  end

  def uploadMessage
    ary = getHpks
    pairary = _get_random_pair(@config[:number_of_mailboxes]-1)
    hpk = b64dec ary[pairary[0]]
    to_hpk = ary[pairary[1]]
    data = {cmd: 'upload', to: to_hpk, payload: 'hello world 0'}
    n = _make_nonce
    @session_key = Rails.cache.read("session_key_#{hpk}")
    @client_key = Rails.cache.read("client_key_#{hpk}")

    skpk = @session_key.public_key
    skpk = b64enc skpk
    ckpk = b64enc @client_key

    _post "/command", hpk, n, _client_encrypt_data(n,data)
  end

  def downloadMessage
    ary = getHpks
    pairary = _get_random_pair(@config[:number_of_mailboxes]-1)
    hpk = b64dec ary[pairary[0]]
    to_hpk = ary[pairary[1]]
    data = {cmd: 'download'}
    n = _make_nonce
    @session_key = Rails.cache.read("session_key_#{hpk}")
    @client_key = Rails.cache.read("client_key_#{hpk}")

    skpk = @session_key.public_key
    skpk = b64enc skpk
    ckpk = b64enc @client_key

    _post "/command", hpk, n, _client_encrypt_data(n,data)
    _success_response

    lines = _check_response(response.body)
    assert_equal(2, lines.length)

    rn = b64dec lines[0]
    rct = b64dec lines[1]
    data = _client_decrypt_data rn,rct

    assert_not_nil data
    assert_equal data.length,0
  end

  def increment_number_of_messages
    redisc.select @config[:testdb]
    numofmessages = @config[:upload_number_of_messages] + 1
    redisc.incrby(@config[:total_number_of_messages],numofmessages)
    redisc.select 0
  end

  def decrement_number_of_messages(numofmessages)
    redisc.select @config[:testdb]
    redisc.decrby(@config[:total_number_of_messages],numofmessages)
    redisc.select 0
  end

  def get_number_of_messages
    redisc.select @config[:testdb]
    numofmessages = redisc.get(@config[:total_number_of_messages])
    redisc.select 0
    numofmessages_mbx = get_total_number_of_messages_across_mbx
    assert_equal(numofmessages.to_i,numofmessages_mbx)
    numofmessages
  end

  # this gets the total number of messages across all mailboxes
  def get_total_number_of_messages_across_mbx
    ary = getHpks
    total_messages = 0
    ary.each do |key|
      mbxkey = 'mbx_' + key
      num_of_messages = redisc.llen(mbxkey)
      print mbxkey, ' ', num_of_messages; puts
      total_messages = total_messages + num_of_messages.to_i
    end
    print 'total messages = ', total_messages; puts
    total_messages
  end

  def setHpks
    cleanup
    for i in 0..@config[:number_of_mailboxes]-1
      hpk = setup_prove
      hpk_b64 = b64enc hpk
      redisc.select @config[:testdb]
      redisc.sadd(@config[:hpkey],hpk_b64)
      redisc.expire(@config[:hpkey],@tmout)
      redisc.select 0
    end
  end

  ### check to see if there are hpks in hpkdb
  def getHpks
    redisc.select @config[:testdb]
    result = redisc.smembers(@config[:hpkey])
    redisc.select 0
    result
  end

  def getConfig
    config = {
      :number_of_mailboxes => 3,
      :upload_number_of_messages => 24,
      :testdb => 5,
      :hpkey => 'hpksdelete',
      :total_number_of_messages => 'hpktotalmessages'
    }
  end

  def cleanup
    redisc.select @config[:testdb]
    redisc.del(@config[:hpkey])
    redisc.del(@config[:total_number_of_messages])
    redisc.select 0
  end

  def _check_response(body)
    raise "No request body" if body.nil?
    nl = body.include?("\r\n") ? "\r\n" : "\n"
    return body.split nl
  end

  private
  def redisc
    Redis.current
  end
end
