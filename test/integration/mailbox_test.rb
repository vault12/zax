require 'test_helper'
require 'mailbox'

class MailboxTest < ActionDispatch::IntegrationTest
  test "mailbox" do
    hpk = RbNaCl::Random.random_bytes 32
    mbx = Mailbox.new hpk

    assert_not_nil mbx.hpk
    assert_equal 0,mbx.top

    for i in (1..5)
      mbx.store h2("#{i}"), "hello_N#{i}"
      assert_equal i,mbx.top
    end

    # [1,2,3,4,5]
    results = mbx.read_all
    assert_equal 5,results.length
    assert_equal 5,mbx.top

    id1 = results[1][:id]
    id3 = results[3][:id]

    assert_equal results[1], mbx.find_by_id(id1)
    assert_equal results[3], mbx.find_by_id(id3)

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
  end

end