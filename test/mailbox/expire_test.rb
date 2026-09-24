# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'
require 'mailbox'

# Message-expiration contract of Mailbox: count/read_all must reflect only
# live messages, the mbx_ index hash must compact expired nonces away, and
# store/delete cycles must keep counts exact.
#
# Redis TTL expiry of a msg_ key is simulated by deleting the key — that is
# observationally identical to expiration for everything downstream, so the
# fast tests need no wall-clock waits. The genuine end-to-end TTL proof runs
# in the SLOW group (set SLOW=1).
class MailboxExpireTest < ActiveSupport::TestCase

  OPTS = { mbx_expire: 60, msg_expire: 30 }.freeze

  setup do
    @from = h2(rand_bytes 32)
    @mailboxes = []
  end

  teardown do
    @mailboxes.each do |mbx|
      rds.del mbx.hpk_tag
      rds.keys("msg_#{mbx.hpk}_*").each { |k| rds.del k }
    end
    rds.del "msg_idx_from_#{@from.to_b64}"
  end

  test 'count and read_all skip expired messages' do
    mbx = _new_mailbox
    stored = 6.times.map { |i| _store(mbx, "msg-#{i}") }
    assert_equal 6, mbx.count

    # Simulate Redis TTL expiry of the first three: delete their msg_ keys
    expired, live = stored[0..2], stored[3..5]
    expired.each { |b64_nonce, _tok| rds.del mbx.msg_tag(b64_nonce) }

    # A fresh Mailbox (as on a new request) sees only the live messages
    fresh = _new_mailbox_for mbx.hpk
    assert_equal 3, fresh.count
    assert_equal %w(msg-3 msg-4 msg-5), fresh.read_all.map { |m| m[:data] }.sort

    # count/_compact reaped the dead nonces out of the mbx_ index hash
    assert_equal 3, rds.hlen(mbx.hpk_tag).to_i

    # Sender-visible status: live messages report a positive TTL, expired -2
    live.each    { |_n, tok| assert_operator fresh.check_msg_status(tok).to_i, :>, 0 }
    expired.each { |_n, tok| assert_equal '-2', fresh.check_msg_status(tok) }
  end

  # the status token must not be a cross-mailbox existence/TTL oracle.
  # Only the message's recipient (hpk_to) or sender (hpk_from) may read its TTL;
  # any other caller gets the same "-2" a missing token yields, even while the
  # message is live.
  test 'check_msg_status is scoped to sender and recipient' do
    recipient = _new_mailbox
    _b64_nonce, tok = _store recipient, 'scoped'

    # Recipient (hpk_to) can check
    assert_operator recipient.check_msg_status(tok).to_i, :>, 0

    # Sender (hpk_from) can check — same token, from their own mailbox
    sender = _new_mailbox_for b64enc(@from)
    assert_operator sender.check_msg_status(tok).to_i, :>, 0

    # An unrelated third party is refused with -2 (indistinguishable from a
    # missing token), even though the message is still live for the parties.
    stranger = _new_mailbox
    assert_equal '-2', stranger.check_msg_status(tok)
    assert_operator recipient.check_msg_status(tok).to_i, :>, 0
  end

  test 'store and delete cycles keep counts consistent' do
    a = _new_mailbox
    b = _new_mailbox
    a_msgs = 4.times.map { |i| _store(a, "a-#{i}") }
    b_msgs = 3.times.map { |i| _store(b, "b-#{i}") }

    assert_equal 4, a.count
    assert_equal 3, b.count

    # Delete a batch from A and a single message from B
    a.delete_list a_msgs[0..1].map(&:first)
    b.delete b_msgs[0].first

    assert_equal 2, a.count
    assert_equal 2, b.count

    # Deleted messages report gone (-2); the rest are intact and readable
    assert_equal '-2', a.check_msg_status(a_msgs[0][1])
    assert_equal %w(a-2 a-3), a.read_all.map { |m| m[:data] }.sort
    assert_equal %w(b-1 b-2), b.read_all.map { |m| m[:data] }.sort
  end

  test 'mailbox rejects msg_expire greater than mbx_expire' do
    assert_raises(ReportError) do
      Mailbox.new b64enc(h2(rand_bytes 32)), { mbx_expire: 10, msg_expire: 20 }
    end
  end

  # The one genuine wall-clock proof: real Redis TTLs set by store()
  test 'messages expire end-to-end with real redis TTLs' do
    skip 'slow lifecycle test: set SLOW=1 to run' unless ENV['SLOW']

    ttl_opts = { mbx_expire: 3, msg_expire: 2 }
    mbx = _new_mailbox ttl_opts
    stored = 3.times.map { |i| _store(mbx, "ttl-#{i}") }
    assert_equal 3, mbx.count

    # The index hash TTL is bounded by mbx_expire
    assert_operator rds.ttl(mbx.hpk_tag), :<=, ttl_opts[:mbx_expire]

    sleep 2.4 # past msg_expire, normally still inside mbx_expire

    stored.each do |b64_nonce, _tok|
      assert_not rds.exists?(mbx.msg_tag(b64_nonce)), 'msg key survived its TTL'
    end
    fresh = _new_mailbox_for mbx.hpk, ttl_opts
    assert_equal 0, fresh.count
    assert_empty fresh.read_all
  end

  private

  def _new_mailbox(options = OPTS.dup)
    _new_mailbox_for b64enc(h2(rand_bytes 32)), options
  end

  def _new_mailbox_for(hpk_b64, options = OPTS.dup)
    mbx = Mailbox.new hpk_b64, options
    @mailboxes << mbx
    mbx
  end

  def _store(mbx, data)
    nonce = rand_bytes 24
    res = mbx.store @from, nonce, data
    [nonce.to_b64, res[:storage_token]]
  end

end
