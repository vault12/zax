# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'json'

class Mailbox
  include Utils
  include TransactionHelper

  # --- HPK and redis storage tags
  attr_reader :hpk

  def hpk_tag
    "mbx_#{@hpk}"
  end

  def msg_tag(b64_nonce)
    "msg_#{@hpk}_#{b64_nonce}"
  end

  # --- create Mailbox for the given HPK with options to override timeouts
  def initialize( hpk, options = {})
    fail HPKError.new self, msg: 'Mailbox: wrong hpk format' unless hpk and hpk.length==HPK_LEN

    @tmout_mbx = options[:mbx_expire] || Rails.configuration.x.relay.mailbox_timeout
    @tmout_msg = options[:msg_expire] || Rails.configuration.x.relay.message_timeout
    fail ReportError.new self, msg: 'Mailbox expire must be greater than or equal to Message expire' if @tmout_msg > @tmout_mbx

    @hpk = b64enc hpk
    @index = {}
    @lastCount = nil
  end

  # number of messages for this mailbox in redis
  # value is volatile: messages can expire at any moment
  def count()
    # @lastCount may over-report just expired items
    # but they will be skipped in read_all
    return @lastCount if @lastCount
    return 0 unless rds.exists hpk_tag
    _compact
    @lastCount = rds.hlen(hpk_tag).to_i
  end

  # Store message for this mailbox. Message sender
  # provides the nonce used in encryption which due to
  # nonce uniqueness is also used as the message id.
  def store(from, nonce, data)
    fail ReportError.new self, msg: 'mailbox.store() : wrong params' unless data and
      from and from.length == HPK_LEN

    b64_from = b64enc from
    b64_nonce = b64enc nonce
    b64_data = b64enc data

    item = {
      from: b64_from,   # hpk of mailbox sending this message
      nonce: b64_nonce, # the nonce originator used for his encryption
      data: b64_data,   # encrypted payload
      time: Time.new.to_f # time message is received by relay
    }

    res = runMbxTransaction(@hpk, 'store') do
      # store message itself on the msg_hpk_nonce tag
      rds.set(msg_tag(b64_nonce), item.to_json)
      rds.expire(msg_tag(b64_nonce), @tmout_msg)

      # mbx_hpk is used as index hash
      rds.hset(hpk_tag, b64_nonce, Time.new + @tmout_msg)
      rds.expire(hpk_tag, @tmout_mbx)
      # by default everytihing in mailbox will expire in 3 days

      _resetCount()
    end
    return res
  end

  # read all or subset of messages in mailbox
  def read_all(start = 0, size = -1)
    a = []
    size = count - start if size == -1
    result = rds.exists hpk_tag
    return a unless result and size > 0

    # read all nonces as list
    nonces = rds.hkeys hpk_tag
    limit = start+size <= nonces.length ? start + size : nonces.length

    # read all messages requested in atomic transaction
    res = runMbxTransaction(@hpk, 'read_all') do
      for i in (start...limit)
        rds.get msg_tag nonces[i]
      end
    end

    # decode each item from base64 and check for null values
    # left by expired messages
    res.each do |item|
      next unless item
      msg = parse item
      yield msg if block_given?
      a.push msg
    end
    return a
  end

  def parse(item)
    return nil if item.nil?
    msg = JSON.parse(item.to_s)
    return Hash[msg.map { |k, v| [ k.to_sym, k != "time" ? b64dec(v) : v ] }]
  end

  # Delete one message by nonce
  def delete(nonce)
    runMbxTransaction(@hpk, 'delete') do
      rds.del msg_tag nonce
      rds.hdel hpk_tag, nonce
      logger.info "#{INFO} deleting #{dumpHex b64dec nonce} in mbx #{dumpHex b64dec @hpk}"
    end
    _resetCount()
  end

  # Delete list of messages by list of nonces
  def delete_list(nonce_list)
    runMbxTransaction(@hpk, 'delete list') do
      nonce_list.each do |nonce|
        rds.del msg_tag nonce
        rds.hdel hpk_tag, nonce
        logger.info "#{INFO} deleting #{dumpHex b64dec nonce} in mbx #{dumpHex b64dec @hpk}"
      end
      _resetCount()
   end
  end

  private

  # messages expire independently of hashed index. we update index
  # and remove nonces for messages that already expired
  def _compact
    nonces = rds.hkeys hpk_tag
    # select all nonces that no longer have corresponding message stored
    toDel = nonces.select { |n| not rds.exists msg_tag n }

    # delete all these nonces from hash index
    unless toDel.empty?
      _resetCount()
      runMbxTransaction(@hpk, 'compact') { toDel.each { |n| rds.hdel hpk_tag, n } }
    end
  end

  def _resetCount()
    @lastCount = nil
  end

  def rds
    Redis.current
  end
end
