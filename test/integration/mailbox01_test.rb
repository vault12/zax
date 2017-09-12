# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'
require 'mailbox'

class Mailbox01Test < ActionDispatch::IntegrationTest
  test 'mailbox expire early with fixed hpk' do
    hpk = h2('vault12.com')
    cleanup(hpk)
    options = {}
    options[:mbx_expire] = 20.seconds.to_i
    options[:msg_expire] = 10.seconds.to_i

    mbx = Mailbox.new hpk.to_b64, options

    assert_not_nil mbx.hpk
    hpkey = "mbx_#{mbx.hpk}"

    for i in (1..5)
      from = h2("#{i}")
      nonce = h2(rand_bytes(16))
      mbx.store from, nonce, "hello_N#{i - 1}"
      assert_equal i, rds.hlen(hpkey)
    end
    cleanup(hpk)
  end

  private

  # download all of the messages stored above
  # and then test the delete command
  def cleanup(hpk)
    mbx = Mailbox.new hpk.to_b64
    results = mbx.read_all
    return unless results
    results_count = results.length
    count = results_count - 1
    results.each do |item|
      mbx.delete item[:nonce].to_b64
      assert_equal(mbx.count, count)
      count -= 1
    end
    assert_equal(mbx.count, 0)
  end
end
