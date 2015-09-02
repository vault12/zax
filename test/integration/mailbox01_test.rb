require 'test_helper'
require 'mailbox'

class Mailbox01Test < ActionDispatch::IntegrationTest

  test "mailbox" do
    hpk = RbNaCl::Random.random_bytes 32
    mbx = Mailbox.new hpk

    assert_not_nil mbx.hpk
    hpkey = "mbx_#{mbx.hpk}"

    for i in (1..5)
      from = h2("#{i}")
      nonce = h2(rand_bytes(16))
      mbx.store from, nonce, "hello_N#{i - 1}"
      assert_equal i,redisc.llen(hpkey)
    end

    for i in (0..4)
      msg = mbx.read(i)
      #puts msg[:from]
      #puts msg[:data]
    end

    #print "mailbox size mbx = ", mbx.count; puts
    #print "mailbox size mbx_cache = ", mbxcache.top; puts

    results = mbx.read_all

    results.each_with_index do |item, i|
      nonce = results[i][:nonce]
#      print 'nonce = ', nonce; puts
      nonce = b64enc nonce
      idx = mbx.idx_by_id(nonce)
#      print idx, " ", item[:data]; puts

      assert_equal(i,idx)
      myitem = mbx.find_by_id(nonce)

#      puts myitem[:data]

      assert_equal(item,myitem)

    end

    results = mbx.read_all

#    print 'count 01 = ', mbx.count; puts
#    print 'count 02 = ', results.length; puts

    assert_equal(mbx.count,results.length)

=begin

    results.each_with_index do |item, i|
      id = results[i][:id]
      idx = mbx.idx_by_id(id)
      assert_equal(i,idx)
      myitem = mbx.find_by_id(id)
      assert_equal(item,myitem)
    end

    assert_equal(results.length,5)
    mbx.delete(2)
    results_del = mbx.read_all
    assert_equal(results_del.length,4)

    results = mbx.read_all
    results.each_with_index do |item, i|
      id = results[i][:id]
      from = results[i][:data]
      print i, " ", from, "  ", id; puts
      #item = mbx.find_by_id(id)
      #print item[:from]; puts

      #mbx.delete_by_id(id)
    end

    #assert_equal(mbx.count,0)


=end


=begin
    # [0,1,2,3,4]
    results = mbx.read_all
    assert_equal 5,results.length
    assert_equal 5,redisc.llen(hpkey)

    id0 = results[0][:id]
    id2 = results[2][:id]

    assert_equal results[0], mbx.find_by_id(id1)
    assert_equal results[2], mbx.find_by_id(id3)

    # [1,nil,3,4,5]
    mbx.delete 1
    results = mbx.read_all
    assert_equal 4,results.length
    assert_equal 5,mbx.top
    assert_nil mbx.read 1

    # [1,nil,3,nil,5]
    mbx.delete_by_id id3
    results = mbx.read_all
    assert_equal 3,results.length
    assert_equal 5,mbx.top
    assert_nil mbx.read 3

    # [1,nil,3,nil,nil] => [1,nil,3]
    mbx.delete 4
    results = mbx.read_all
    assert_equal 2,results.length
    assert_equal 3,mbx.top
    assert_nil mbx.read 4

    # [1,nil,3,6]
    id6 = mbx.store(h2('6'),"hello_N6")[:id]
    results = mbx.read_all
    assert_equal 3,results.length
    assert_equal 4,mbx.top
    assert_equal 3, mbx.idx_by_id(id6)
=end
  end

end
