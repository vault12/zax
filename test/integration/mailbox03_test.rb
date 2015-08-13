require 'test_helper'
require 'mailbox'

class Mailbox03Test < ActionDispatch::IntegrationTest
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

    results.each do |item|
      id = b64enc item[:nonce]
      mbx.delete_by_id(id)
    end

    assert_equal(mbx.count,0)
  end
end
