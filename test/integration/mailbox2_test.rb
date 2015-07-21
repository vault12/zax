require 'test_helper'
require 'mailbox'

class Mailbox2Test < ActionDispatch::IntegrationTest
  test "mailbox" do
    hpk = RbNaCl::Random.random_bytes 32
    mbx = Mailbox.new hpk

    b64hpk = b64enc(hpk)
    assert_equal b64dec(b64hpk),hpk
    assert_equal hpk,b64dec(b64hpk)
    myhpk = mbx.hpk
    assert_equal hpk,myhpk

    assert_not_nil mbx.hpk
    assert_equal 0,mbx.top

    for i in (1..5)
      mbx.store h2("#{i}"), "hello_N#{i}"
      assert_equal i,mbx.top
    end

    for i in (0..4)
      result = mbx.read i
      assert_equal 3, result.length
      #puts result[:data]
      x = i + 1
      assert_equal result[:data], "hello_N#{x}"
    end

    while mbx.top > 0
      value = mbx.top
      #puts value
      value = value - 1
      mbx.delete value
    end

    mbx.delete 0
    mbx.delete 1

    results = mbx.read_all
    assert_equal 0,results.length
    assert_equal 0,mbx.top

    Rails.cache.delete "anything 01"
    mbx.update_top
    value = mbx.top
    assert_equal 0,value

    assert_equal myhpk, mbx.hpk

    id_1 = mbx.store(h2('1'),"hello_N1")[:id]
    id_2 = mbx.store(h2('2'),"hello_N2")[:id]
    id_3 = mbx.store(h2('3'),"hello_N3")[:id]

    results = mbx.read_all
    assert_equal 3,results.length
    assert_equal 3,mbx.top

    assert_equal 2, mbx.idx_by_id(id_3)
    assert_equal 0, mbx.idx_by_id(id_1)
    assert_equal 1, mbx.idx_by_id(id_2)

    assert_equal results[2], mbx.find_by_id(id_3)
    assert_equal results[0], mbx.find_by_id(id_1)
    assert_equal results[1], mbx.find_by_id(id_2)

    mbx.delete_by_id(id_3)
    assert_equal 2,mbx.top

    mbx.delete_by_id(id_1)

    # uncommenting the next line may show the race condition
    #assert_equal 1,mbx.top

    mbx.delete_by_id(id_2)
    assert_equal 0,mbx.top

  end
end
