require 'test_helper'
require 'prove_test_helper'

class MultipleHpkTest < ProveTestHelper

  test "multiple hpk storage in redis" do
    @config = {
      :number_of_mailboxes => 3,
      :testdb => 5,
      :hpkey => 'hpks'
    }
    ary = getHpks
    setHpks if ary.length == 0
    for i in 0..25
      sendMessage
    end
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

    skpk = @session_key.public_key
    skpk = b64enc skpk
    ckpk = b64enc @client_key
    #print 'session key ',skpk; puts
    #print 'client key ',ckpk; puts; puts

    _post "/command", hpk, n, _clientest_encrypt_data(n,data)
  end

  def setHpks
    for i in 0..@config[:number_of_mailboxes]-1
      hpk = setup_prove
      redisc.select @config[:testdb]
      hpk_b64 = b64enc hpk
      redisc.sadd(@config[:hpkey],hpk_b64)
      redisc.select 0
      _setup_keys hpk
      to_hpk = RbNaCl::Random.random_bytes(32)
      to_hpk = b64enc to_hpk
      data = {cmd: 'upload', to: to_hpk, payload: 'hello world 0'}
      n = _make_nonce
      _post "/command", hpk, n, _client_encrypt_data(n,data)
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

  def _clientest_encrypt_data(nonce,data)
    box = RbNaCl::Box.new(@client_key, @session_key)
    box.encrypt(nonce,data.to_json)
  end

  def redisc
    Redis.current
  end
end
