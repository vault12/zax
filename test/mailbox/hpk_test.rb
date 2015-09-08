require 'test_helper'
require 'prove_test_helper'

class MultipleHpkTest < ProveTestHelper

  test "multiple hpk storage in redis" do
    @config = {
      :number_of_mailboxes => 3,
      :number_of_messages => 24,
      :testdb => 0,
      :hpkey => 'hpks',
      :number_of_iterations => 'hpkiteration'
    }
    ary = getHpks
    setHpks if ary.length == 0
    for i in 0..@config[:number_of_messages]
      sendMessage
    end
    check_number_of_messages
  end

  def sendMessage
    ary = getHpks
    pairary = _get_random_pair(@config[:number_of_mailboxes]-1)
    hpk = b64dec ary[pairary[0]]
    to_hpk = ary[pairary[1]]
    data = {cmd: 'upload', to: to_hpk, payload: 'hello world 0'}
    n = _make_nonce
    @session_key = Rails.cache.read("session_key_#{hpk}")
    @client_key = Rails.cache.read("client_key_#{hpk}")

    #print 'hpk ', ary[pairary[0]]; puts
    #print 'to_hpk ', to_hpk; puts

    # TODO Fix this when the above 2 keys have expired
    # TODO fire up a whole new test infrastructure with new keys et al
    # TODO for now the simple solution to fix this is to do a flushall
    skpk = @session_key.public_key
    skpk = b64enc skpk
    ckpk = b64enc @client_key
    #print 'session key ',skpk; puts
    #print 'client key ',ckpk; puts; puts

    _post "/command", hpk, n, _client_encrypt_data(n,data)
  end

  def check_number_of_messages
    redisc.select @config[:testdb]
    iterations = redisc.get(@config[:number_of_iterations])
    if iterations.nil?
      print 'iterations = 1'; puts
      redisc.set(@config[:number_of_iterations],1)
    else
      iterations = iterations.to_i + 1
      print 'iterations = ', iterations; puts
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
    redisc.select 0
    ary.each do |key|
      mbxkey = 'mbx_' + key
      redisc.select 0
      num_of_messages = redisc.llen(mbxkey)
      print mbxkey, ' ', num_of_messages; puts
      total_messages = total_messages + num_of_messages.to_i
    end
    print 'total messages = ', total_messages; puts
    total_messages
  end

  def setHpks
    for i in 0..@config[:number_of_mailboxes]-1
      hpk = setup_prove
      hpk_b64 = b64enc hpk
      redisc.select @config[:testdb]
      redisc.sadd(@config[:hpkey],hpk_b64)
      redisc.select 0
=begin
      _setup_keys hpk
      to_hpk = RbNaCl::Random.random_bytes(32)
      to_hpk = b64enc to_hpk
      data = {cmd: 'upload', to: to_hpk, payload: 'hello world 0'}
      n = _make_nonce
      _post "/command", hpk, n, _client_encrypt_data(n,data)
=end
    end
  end

  ### check to see if there are hpks in hpkdb
  def getHpks
    redisc.select @config[:testdb]
    result = redisc.smembers(@config[:hpkey])
    redisc.select 0
    result
  end

  private
  def redisc
    Redis.current
  end
end
