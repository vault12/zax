# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'
require 'mailbox'

class MailboxBasicTest < ActionDispatch::IntegrationTest
  include Helpers::TransactionHelper

  test 'basic functionality upload count download delete' do
    @config = getConfig
    setHpks
    for i in 0..@config[:upload_number_of_messages]
      uploadMessage
      countMessages
      downloadMessages
    end
    checkClean
  end

  # a malformed base64 id in a delete batch must not abort the whole
  # transaction (the log line used to decode it and raise mid-MULTI, discarding
  # every valid deletion). The bad id is a harmless no-op; valid ones delete.
  test 'delete_list tolerates a malformed nonce without dropping the batch' do
    from = h2(rand_bytes(16))
    mbx  = Mailbox.new b64enc(h2(rand_bytes(16)))
    n1, n2 = rand_bytes(24), rand_bytes(24)
    mbx.store from, n1, 'one'
    mbx.store from, n2, 'two'
    assert_equal 2, mbx.count

    # 'not strict b64 !!' fails Base64.strict_decode64 => the old log decode
    # would raise ArgumentError inside the MULTI and drop n1 and n2 too.
    mbx.delete_list [n1.to_b64, 'not strict b64 !!', n2.to_b64]
    assert_equal 0, mbx.count, 'both valid messages deleted despite the bad id'

    rds.del mbx.hpk_tag
    rds.del "msg_idx_from_#{b64enc from}"
  end

  # a mailbox written to but never read must not accumulate index
  # entries for expired messages. store() reaps them (reap-on-write).
  test 'store reaps index entries of expired messages without a read' do
    hpk  = h2(rand_bytes(16)) # 32-byte recipient hpk
    from = h2(rand_bytes(16)) # 32-byte sender hpk
    mbx  = Mailbox.new b64enc(hpk)

    nonces = Array.new(3) { rand_bytes(24) }
    nonces.each { |n| mbx.store from, n, 'hello' }
    assert_equal 3, rds.hlen(mbx.hpk_tag)

    # Simulate expiry of the first two messages: the msg_ keys are gone but the
    # index fields remain (nothing has read/compacted this mailbox yet).
    rds.del mbx.msg_tag(nonces[0].to_b64)
    rds.del mbx.msg_tag(nonces[1].to_b64)
    assert_equal 3, rds.hlen(mbx.hpk_tag), 'index not yet reaped before a write'

    # A new write reaps the two dead fields — with no count()/read_all() call.
    mbx.store from, rand_bytes(24), 'hello again'
    assert_equal 2, rds.hlen(mbx.hpk_tag), 'expired fields reaped on write, 1 live + 1 new'

    rds.del mbx.hpk_tag
  end

  # Concurrent WATCH/MULTI transactions must not lose updates. With a
  # single shared connection the watch is cleared between WATCH and EXEC, so
  # stale writes commit silently and the final counter is < n. With a per-thread
  # pooled connection each conflict aborts and retries, so every increment lands.
  # (mailbox_retry is raised so the assertion isolates lost-updates from
  # legitimate retry exhaustion under contention.)
  test 'concurrent WATCH transactions do not lose updates' do
    saved = Rails.configuration.x.relay.mailbox_retry
    Rails.configuration.x.relay.mailbox_retry = 50
    key = "zax004_counter_#{rand_bytes(8).unpack1('H*')}" 
    rds.set key, 0
    n = 6

    start = false
    threads = Array.new(n) do
      Thread.new do
        true while not start # release all threads together to force contention
        runRedisTransaction(key, nil, 'incr', Proc.new { rds.get(key).to_i }) do |current, tx|
          tx.set key, current + 1
        end
      end
    end
    start = true
    threads.each(&:join)

    assert_equal n, rds.get(key).to_i, 'every concurrent increment landed'
    rds.del key
  ensure
    Rails.configuration.x.relay.mailbox_retry = saved
  end

  # a single originator (sender hpk) cannot keep more than
  # max_messages live messages, counted across all recipient mailboxes.
  test 'per-sender message cap is enforced across recipients' do
    saved = Rails.configuration.x.relay.max_messages
    Rails.configuration.x.relay.max_messages = 3
    from = h2(rand_bytes(16)) # one sender

    # Store up to the cap, each to a DIFFERENT recipient (proves it's per-sender,
    # not per-mailbox).
    recipients = Array.new(3) { Mailbox.new b64enc(h2(rand_bytes(16))) }
    recipients.each { |mbx| mbx.store from, rand_bytes(24), 'hi' }

    # A 4th message from the same sender — even to a brand-new mailbox — is rejected.
    over = Mailbox.new b64enc(h2(rand_bytes(16)))
    assert_raises(ReportError) { over.store from, rand_bytes(24), 'over limit' }

    # A different sender is unaffected.
    other = h2(rand_bytes(16))
    recipients.first.store other, rand_bytes(24), 'from someone else'

    recipients.each { |mbx| rds.del mbx.hpk_tag }
    rds.del over.hpk_tag
    rds.del mbx_send_index(from)
    rds.del mbx_send_index(other)
  ensure
    Rails.configuration.x.relay.max_messages = saved
  end

  # a concurrent burst from one sender to diff
  # recipients must not overshoot max_messages. sender index is watched,
  # so concurrent commits conflict, retry, and re-check against fresh state.
  test 'per-sender message cap holds under a concurrent burst' do
    saved_max   = Rails.configuration.x.relay.max_messages
    saved_retry = Rails.configuration.x.relay.mailbox_retry
    Rails.configuration.x.relay.max_messages  = 5
    Rails.configuration.x.relay.mailbox_retry = 50 # isolate the invariant from retry exhaustion

    from = h2(rand_bytes(16))                    # one sender
    n = 12                                        # well over the cap of 5
    recipients = Array.new(n) { Mailbox.new b64enc(h2(rand_bytes(16))) }

    start = false
    rejected = Queue.new                          # thread-safe tally of over-cap refusals
    threads = recipients.map do |mbx|
      Thread.new do
        true while not start                      # release together to force contention
        begin
          mbx.store from, rand_bytes(24), 'burst'
        rescue ReportError
          rejected << 1                           # over-cap stores are correctly refused
        end
      end
    end
    start = true
    threads.each(&:join)

    # Authoritative count of what actually committed: the sender's live index.
    committed = rds.hlen(mbx_send_index(from)).to_i
    assert_equal 5, committed, "cap filled exactly, never overshot (got #{committed})"
    assert_equal n - 5, rejected.size, 'every store beyond the cap was rejected'
  ensure
    recipients&.each { |mbx| rds.del mbx.hpk_tag }
    rds.del mbx_send_index(from)
    Rails.configuration.x.relay.max_messages  = saved_max
    Rails.configuration.x.relay.mailbox_retry = saved_retry
  end

  # recipient mailbox cannot exceed max_messages. The sender is told specifically it is full.
  test 'per-recipient mailbox cap blocks flooding by many senders' do
    saved = Rails.configuration.x.relay.max_messages
    Rails.configuration.x.relay.max_messages = 4
    victim = Mailbox.new b64enc(h2(rand_bytes(16)))

    # Fill the mailbox to the cap using a DIFFERENT sender each time — proves the
    # bound is per-recipient, not per-sender (one fresh identity per message).
    senders = Array.new(4) { h2(rand_bytes(16)) }
    senders.each { |s| victim.store s, rand_bytes(24), 'hi' }
    assert_equal 4, rds.hlen(victim.hpk_tag)

    # A brand-new sender, nowhere near its OWN per-sender cap, is still refused —
    # with the specific mailbox-full signal the client can act on.
    newcomer = h2(rand_bytes(16))
    err = assert_raises(MailboxFullError) { victim.store newcomer, rand_bytes(24), 'flood' }
    assert_equal 'Destination mailbox is full', err.client_detail
    assert_equal 4, rds.hlen(victim.hpk_tag), 'no overshoot; the flood message did not land'

    # Draining one message reopens exactly one slot.
    victim.delete rds.hkeys(victim.hpk_tag).first
    victim.store newcomer, rand_bytes(24), 'now there is room'
    assert_equal 4, rds.hlen(victim.hpk_tag)
  ensure
    rds.del victim.hpk_tag if victim
    senders&.each { |s| rds.del mbx_send_index(s) }
    rds.del mbx_send_index(newcomer) if defined?(newcomer) && newcomer
    Rails.configuration.x.relay.max_messages = saved
  end

  # a malformed HPK must raise the real HpkError (the old code
  # referenced undefined constants HPKErr/HPKError => NoMethodError/NameError)
  test 'mailbox rejects malformed hpk cleanly' do
    assert_raises(HpkError) { Mailbox.new 'way-too-short' }
    assert_raises(HpkError) { Mailbox.new nil }
  end

  # delete must remove the storage-token record. The old code
  # deleted a never-created raw-bytes key (missing token_ prefix + b64),
  # orphaning the real token_<b64> record until its TTL.
  test 'delete removes the storage token record' do
    from = h2(rand_bytes(16))
    mbx = Mailbox.new b64enc(h2(rand_bytes(16)))
    nonce = rand_bytes(24)

    res = mbx.store from, nonce, 'to be deleted'
    token_key = mbx.token_tag(res[:storage_token])
    assert rds.exists?(token_key), 'token record created by store'

    mbx.delete nonce.to_b64
    assert_not rds.exists?(token_key), 'token record deleted with the message'

    rds.del mbx.hpk_tag
    rds.del "msg_idx_from_#{b64enc from}"
  end

  # the stored-message nonce IS the message id — reuse must fail
  # instead of silently overwriting the queued message, and the nonce must be
  # protocol-sized (24 bytes).
  test 'store rejects nonce reuse and malformed nonces' do
    from = h2(rand_bytes(16))
    mbx  = Mailbox.new b64enc(h2(rand_bytes(16)))
    nonce = rand_bytes(24)

    mbx.store from, nonce, 'first'
    assert_raises(ReportError) { mbx.store from, nonce, 'clobber attempt' }

    # The original message is untouched by the rejected overwrite
    msgs = mbx.read_all
    assert_equal 1, msgs.length
    assert_equal 'first', msgs[0][:data]

    # Wrong-length nonces are rejected outright
    assert_raises(ReportError) { mbx.store from, rand_bytes(32), 'long nonce' }
    assert_raises(ReportError) { mbx.store from, rand_bytes(23), 'short nonce' }
    assert_raises(ReportError) { mbx.store from, '', 'empty nonce' }

    # Once the message is deleted its nonce is free again (key is gone)
    mbx.delete nonce.to_b64
    mbx.store from, nonce, 'second life'
    assert_equal 'second life', mbx.read_all[0][:data]

    rds.del mbx.hpk_tag
    rds.del mbx.msg_tag(nonce.to_b64)
    rds.del mbx_send_index(from)
  end

  private

  def mbx_send_index(from)
    "msg_idx_from_#{b64enc from}"
  end

  def uploadMessage
    ary = getHpks
    pairary = _get_random_pair(@config[:number_of_mailboxes] - 1)
    hpk = ary[pairary[0]].from_b64
    from = ary[pairary[1]].from_b64

    options = {}
    options[:mbx_expire] = 20.seconds.to_i
    options[:msg_expire] = 10.seconds.to_i

    mbx = Mailbox.new b64enc(hpk), options
    assert_not_nil mbx.hpk
    nonce = rand_bytes(24)
    mbx.store from, nonce, "hello from #{ary[pairary[1]]}"
  end

  def countMessages
    ary = getHpks
    ary.each do |hpk|
      mbx = Mailbox.new hpk
    end
  end

  def downloadMessages
    ary = getHpks
    total = 0
    ary.each do |hpk|
      mbx = Mailbox.new hpk
      download = mbx.read_all
      total += download.length
      deleteMessages(mbx, download)
    end
  end

  def deleteMessages(mbx, download_ary)
    download_ary.each do |msg|
      nonce = b64enc msg[:nonce]
      value = mbx.delete(nonce)
    end
  end

  def checkClean
    rds.del(@config[:hpkey])
  end

  def setHpks
    for i in 0..@config[:number_of_mailboxes] - 1
      hpk = h2(rand_bytes(32)) 
      hpk_b64 = b64enc hpk
      rds.sadd(@config[:hpkey], hpk_b64)
    end
  end

  def getHpks
    result = rds.smembers(@config[:hpkey])
  end

  def getConfig
    # Per-run-unique key so parallel suites on one Redis don't share the set.
    # @config is built once per test, so the suffix is stable.
    config = {
      number_of_mailboxes: 3,
      upload_number_of_messages: 24,
      hpkey: "hpksdelete_#{rand_bytes(8).unpack1('H*')}"
    }
  end

end
