require 'test_helper'
require 'mailbox'

class Mailbox02Test < ActionDispatch::IntegrationTest
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

    results = mbx.read_all
    results_count = results.length

    count = results_count - 1
    while count >=0
      mbx.delete(count)
      count-=1
    end

    assert_equal(mbx.count,0)
  end
end
