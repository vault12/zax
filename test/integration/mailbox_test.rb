require 'test_helper'
require 'mailbox'

class MailboxTest < ActionDispatch::IntegrationTest
  test "Test mailbox" do
    hpk = RbNaCl::Random.random_bytes 32
    mbx = Mailbox.new hpk

    assert_not_nil mbx.hpk
    assert_equal 0,mbx.count

    mbx.store "hello"
    assert_equal 1,mbx.count

    mbx.store "world"
    assert_equal 2,mbx.count
  end

end