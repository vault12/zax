require 'test_helper'
require 'prove_test_helper'

class MailboxDeleteTest < ProveTestHelper

  test "upload messages to mailbox for delete" do
    @config = getConfig
    @tmout = Rails.configuration.x.relay.session_timeout - 5
    ary = getHpks
    setHpks if ary.length == 0
    for i in 0..@config[:number_of_messages]
      uploadMessage
    end
    check_number_of_messages
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

  def check_number_of_messages
    redisc.select @config[:testdb]
    iterations = redisc.get(@config[:number_of_iterations]).to_i
    if iterations.nil?
      redisc.set(@config[:number_of_iterations],1)
      iterations = 1
    else
      iterations = iterations.to_i + 1
      redisc.set(@config[:number_of_iterations],iterations)
    end
    redisc.select 0
    total_messages = get_total_number_of_messages
    numofmessages = @config[:number_of_messages] + 1
    total_messages_calc = iterations * numofmessages
    assert_equal(total_messages,total_messages_calc)
  end

  # this gets the total number of messages across all mailboxes
  def get_total_number_of_messages
    ary = getHpks
    total_messages = 0
    ary.each do |key|
      mbxkey = 'mbx_' + key
      num_of_messages = redisc.llen(mbxkey)
      #print mbxkey, ' ', num_of_messages; puts
      total_messages = total_messages + num_of_messages.to_i
    end
    #print 'total messages = ', total_messages; puts
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
      :number_of_messages => 24,
      :testdb => 5,
      :hpkey => 'hpksdelete',
      ### This is going away, will be changed to total messages
      :number_of_iterations => 'hpkiterationdelete'
    }
  end

  def cleanup
    redisc.select @config[:testdb]
    redisc.flushdb
    redisc.select 0
  end

  private
  def redisc
    Redis.current
  end
end
