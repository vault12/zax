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

    generate_mbx(mbx,5)

    for i in (0..4)
      result = mbx.read i
      assert_equal 3, result.length
      #puts result[:data]
      x = i + 1
      assert_equal result[:data], "id_#{x}"
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

    id_1 = mbx.store(h2('1'),"id_1")[:id]
    id_2 = mbx.store(h2('2'),"id_2")[:id]
    id_3 = mbx.store(h2('3'),"id_3")[:id]

    # [1,2,3]
    results = mbx.read_all
    assert_equal 3,results.length
    assert_equal 3,mbx.top

    assert_equal 2, mbx.idx_by_id(id_3)
    assert_equal 0, mbx.idx_by_id(id_1)
    assert_equal 1, mbx.idx_by_id(id_2)

    assert_equal results[2], mbx.find_by_id(id_3)
    assert_equal results[0], mbx.find_by_id(id_1)
    assert_equal results[1], mbx.find_by_id(id_2)

    #[1,2,3] -> [1,2]
    mbx.delete_by_id(id_3)
    assert_equal 2,mbx.top

    # [1,2] -> [nil,1]
    mbx.delete_by_id(id_1)
    assert_equal 2,mbx.top

    #[nil,1,2,3,4]
    id_4 = mbx.store(h2('4'),"id_4")[:id]
    id_5 = mbx.store(h2('5'),"id_5")[:id]
    id_6 = mbx.store(h2('6'),"id_6")[:id]

    assert_equal 5,mbx.top

    results = mbx.read_all
    assert_equal 4, results.length

    mbx.delete_by_id(id_5)
    #[nil,1,2,3,4] -> [nil,1,2,nil,4]

    results = mbx.read_all
    assert_equal 3, results.length
    assert_equal 5, mbx.top

    results.each_with_index do |item,i|
      print i,' ',item[:data]; puts
    end

    #[nil,1,2,nil,4,5]
    id_7 = mbx.store(h2('7'),"id_7")[:id]
    results = mbx.read_all
    assert_equal 4, results.length
    assert_equal 6, mbx.top

    print_mbx(mbx)

    mbx.delete(5)
    mbx.delete(4)
    assert_equal 3, mbx.top
    results = mbx.read_all
    assert_equal 2, results.length

    print_mbx(mbx)

    mbx.delete(1)
    mbx.delete(2)
    assert_equal 0,mbx.top

    generate_mbx(mbx,100)
    assert_equal 100,mbx.top
    results = mbx.read_all
    assert_equal 100,results.length

    mbx.delete(50)
    assert_equal 100,mbx.top
    results = mbx.read_all
    assert_equal 99,results.length

    print_mbx(mbx)
    mbx.delete(99)
    assert_equal 99,mbx.top
    mbx.delete(50)
    assert_equal 99,mbx.top

    mbx.delete(49)
    assert_equal 99,mbx.top

    print_mbx(mbx)
    mbx.delete(98)
    assert_equal 98,mbx.top
    print_mbx(mbx)
  end

  def print_mbx(mbx)
    puts
    for i in (0...mbx.top)
      myid = mbx.read(i)
      if myid
        print i, " ", myid[:data]; puts
      else
        puts i
      end
    end
  end

  def generate_mbx(mbx,num_of_items)
    for i in (1..num_of_items)
      mbx.store h2("#{i}"), "id_#{i}"
      assert_equal i,mbx.top
    end
  end
end
