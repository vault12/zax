# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'
require 'mailbox'

class Mailbox03Test < ActionDispatch::IntegrationTest
  test 'mailbox upload, download and delete' do
    hpk = RbNaCl::Random.random_bytes 32
    mbx = Mailbox.new hpk
    assert_not_nil mbx.hpk
    hpkey = "mbx_#{mbx.hpk}"

    for i in (1..5)
      from = h2("#{i}")
      nonce = h2(rand_bytes(16))
      mbx.store from, nonce, "hello_N#{i - 1}"
      assert_equal i, rds.hlen(hpkey)
    end

    # Download all of the messages you just uploaded
    results = mbx.read_all

    # And then go ahead and delete them
    results.each do |item|
      id = b64enc item[:nonce]
      mbx.delete(id)
    end

    # Make sure all of the messages got deleted
    assert_equal(mbx.count, 0)
  end
end
