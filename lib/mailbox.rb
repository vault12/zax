# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'json'

class Mailbox
  include Utils
  include Helpers::TransactionHelper

  # --- HPK and redis storage tags
  attr_reader :hpk

  # redis hash of all messages to given hpk
  def hpk_tag
    "mbx_#{@hpk}"
  end

  # redis key for specific message to hpk
  def msg_tag(b64_nonce)
    "msg_#{@hpk}_#{b64_nonce}"
  end

  # message storage token that can be inspected
  # later by sender
  def token_tag(token)
    "token_#{token.to_b64}"
  end

  # redish hash of all file info messages sent to/from hpk
  def file_index_to
    "file_idx_to_#{@hpk}"
  end

  def file_index_from(hpk_from)
    "file_idx_from_#{hpk_from}"
  end

  def storage_tag(storage_name)
    "#{STORAGE_PREFIX}#{storage_name}"
  end

  def file_lock_tag(storage_id)
    "file_lock_#{storage_id.to_b64}"
  end

  # --- create Mailbox for the given HPK with options to override timeouts
  def initialize( hpk_b64, options = {})
    unless hpk_b64 and hpk_b64.length == HPK_B64
      fail HPKErr        msg: 'Mailbox: wrong hpk format',
        hpk: hpk_b64
    end

    @tmout_mbx = options[:mbx_expire] || Rails.configuration.x.relay.mailbox_timeout
    @tmout_msg = options[:msg_expire] || Rails.configuration.x.relay.message_timeout
    fail ReportError.new self, msg: 'Mailbox expire must be greater than or equal to Message expire' if @tmout_msg > @tmout_mbx

    @tmout_files = options[:files_expiration] || Rails.configuration.x.relay.file_store[:files_expiration]
    if FileManager.is_enabled? and not @tmout_files
      @tmout_files = 7.days.seconds.to_i
      logger.warn "#{WARN} Missing config setting: FileManager is enabled, yet :files_expiration is not set. Defaulting to #{@tmout_files}"
    end

    @hpk = hpk_b64
    @lastCount = nil
  end

  def timeout(kind)
    return @tmout_msg if kind == :message
    return @tmout_files if kind == :file
  end

  # number of messages for this mailbox in redis
  # value is volatile: messages can expire at any moment
  def count()
    # @lastCount may over-report just expired items
    # but they will be skipped in read_all
    return @lastCount if @lastCount
    return 0 unless rds.exists? hpk_tag
    _compact
    @lastCount = rds.hlen(hpk_tag).to_i
  end

  # Store message for this mailbox. Message sender
  # provides the nonce used in encryption which due to
  # nonce uniqueness is also used as the message id.
  def store(from, nonce, data, kind = :message, extra = {})
    _check_preconditions(from,nonce,data,kind)
    data.force_encoding 'utf-8'

    b64_nonce = nonce.to_b64
    item = {
      from: from.to_b64,        # hpk of mailbox sending this message
      nonce: b64_nonce,         # the nonce originator used for his encryption
      data: data.to_b64,        # encrypted payload
      time: Time.new.to_f,      # time message is received by relay
      kind: kind.to_s.to_b64   # type of data: message or file
    }

    # Using storage record token sender can check
    # status of her message
    storage_record = {
      hpk: @hpk,
      nonce: b64_nonce
    }
    storage_token = h2 "#{@hpk}#{b64_nonce}"

    _resetCount()
    tmout = timeout(kind)
    file_info = nil
    storage_id = nil

    res = runRedisTransaction(hpk_tag, @hpk, 'store') do |_file_info, rds_transaction|
      # by default everytihing in mailbox will expire in 3 days
      # files will expire in 7 days

      # store message itself on the msg_hpk_nonce tag
      rds_transaction.set(msg_tag(b64_nonce), item.to_json)
      rds_transaction.expire(msg_tag(b64_nonce), tmout)

      # mbx_hpk is used as index hash of all messages to @hpk
      rds_transaction.hset(hpk_tag, b64_nonce, (Time.new + tmout).to_s)
      rds_transaction.expire(hpk_tag, tmout)

      # store unique storage token for that item
      # visible to sender (hpk_from) when stored or deleted by @hpk
      rds_transaction.set(token_tag(storage_token), storage_record.to_json)
      rds_transaction.expire(token_tag(storage_token), tmout)

      # :file message is same as other messages handled by relays,
      # which additionally passes to hpk_to 'uploadID' that it can
      # use to issue file commands to relay.
      if kind == :file
        # Relay can easily re-create storage_id from uploadID (kept
        # only by client) and FileManeger @seed, but relay can not
        # restore uploadID from various saved storage_id's
        storage_id = extra[:storage_id]
        storage_name = extra[:storage_name]
        file_info = {
          status: :START,
          parts: [],
          file_size: extra[:file_size],
          bytes_stored: 0,
          hpk_to: @hpk,
          hpk_from: extra[:hpk_from].to_b64,
          total_chunks: 0 # Nothing received yet
        }

        # file_index to/from hpk is used as index hash of all files
        save_file_info(file_info, extra[:hpk_from], storage_id, rds_transaction) if file_info and kind == :file
        save_file_tracking_info(storage_name, tmout, rds_transaction)
      end
    end

    return { opResult: res, storage_token: storage_token }
  end

  # Is message for given storage token still in redis?
  def check_msg_status(storage_token)
    tag = token_tag storage_token
    storage_item = parse rds.get tag
    return "-2" unless storage_item # following redis TTL codes
    mbx = Mailbox.new storage_item[:hpk].to_b64
    ttl = rds.ttl mbx.msg_tag storage_item[:nonce].to_b64
    return "#{ttl}"
  end

  def file_status_from_uid(uploadID, file_manager)
    file_status file_manager.storage_from_upload(uploadID).to_b64
  end

  def file_status(storage_id_b64)
    # logger.info "file_index_to: #{MAGENTA}#{file_index_to}#{ENDCLR}"
    # logger.info "file_index_from: #{MAGENTA}#{file_index_from(@hpk)}#{ENDCLR}"

    # File might be sent by @hpk or from @hpk - checking both
    res = rds.hget file_index_to, storage_id_b64
    res = rds.hget file_index_from(@hpk), storage_id_b64 unless res
    res = res ? JSON.parse(res, symbolize_names: true) : nil
    res = { status: :NOT_FOUND, bytes_stored: 0, parts: [] } unless res
    return res
  end

  def save_file_info(file_info, hpk_from, storage_id, rds_transaction)
    file_info_js = file_info.to_json
    tmout = timeout(:file)

    # file_index to/from hpk is used as index hash of all files
    rds_transaction.hset(file_index_to, storage_id.to_b64, file_info_js)
    rds_transaction.expire(file_index_to, tmout)

    fidx_from = file_index_from(hpk_from.to_b64)
    rds_transaction.hset(fidx_from, storage_id.to_b64, file_info_js)
    rds_transaction.expire(fidx_from, tmout)
  end

  def save_file_tracking_info(storage_name, tmout, rds_transaction)
    # global index is used by workers to clear out expired files
    rds_transaction.sadd(ZAX_GLOBAL_FILES, storage_tag(storage_name))

    # When storage tag expires but still present
    # in persitent GLOBAL worker will delete the file
    # and remove from GLOBAL set
    rds_transaction.set(storage_tag(storage_name), 1)
    rds_transaction.expire(storage_tag(storage_name), tmout)

    cleanup = DateTime.now + timeout(:file).seconds + 10.minutes
    FilesCleanupJob.set(wait_until: cleanup).perform_later
  end

  def delete_file_info(hpk_from, storage_id)
    rds.hdel(file_index_to, storage_id.to_b64)

    fidx_from = file_index_from(hpk_from.to_b64)
    rds.hdel(fidx_from, storage_id.to_b64)
  end

  # read all or subset of messages in mailbox
  def read_all(start = 0, size = -1)
    a = []
    size = count - start if size == -1
    result = rds.exists? hpk_tag
    return a unless result and size > 0

    # read all nonces as list
    nonces = rds.hkeys hpk_tag
    limit = start+size <= nonces.length ? start + size : nonces.length

    # read all messages requested in atomic transaction
    res = runRedisTransaction(hpk_tag, @hpk, 'read_all') do |_file_info, rds_transaction|
      for i in (start...limit)
        rds_transaction.get msg_tag nonces[i]
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
    return Hash[msg.map { |k, v| [ k.to_sym, k != "time" ? v.from_b64.force_encoding('utf-8') : v ] }]
  end

  def _delete_item(nonce, rds_transaction)
    rds_transaction.del msg_tag nonce
    rds_transaction.hdel hpk_tag, nonce
    rds_transaction.del h2 "#{@hpk}#{nonce}" # storage_token
  end

  # Delete one message by nonce
  def delete(nonce)
    _resetCount()
    runRedisTransaction(hpk_tag, @hpk, 'delete') do |_file_info, rds_transaction|
      _delete_item nonce, rds_transaction
      logger.info "#{INFO} #{RED}deleting #{GREEN}#{dumpHex nonce.from_b64}#{ENDCLR} in mbx #{MAGENTA}#{dumpHex @hpk.from_b64}#{ENDCLR}"
    end
  end

  # Delete list of messages by list of nonces
  def delete_list(nonce_list)
    _resetCount()
    runRedisTransaction(hpk_tag, @hpk, 'delete list') do |_file_info, rds_transaction|
      nonce_list.each do |nonce|
        _delete_item nonce, rds_transaction
        logger.info "#{INFO} #{RED}deleting #{GREEN}#{dumpHex nonce.from_b64}#{ENDCLR} in mbx #{MAGENTA}#{dumpHex @hpk.from_b64}#{ENDCLR}"
      end
    end
  end

  private

  def _check_preconditions(from, nonce, data, kind)
    unless data and from and from.length == HPK_LEN and nonce and
      (kind == :message or kind == :file)
      fail ReportError.new self, msg: 'mailbox.store() : wrong params'
    end

    if kind == :file and not FileManager.is_enabled?
      fail ReportError.new self, msg: 'Mailbox receives file command while FileManager is not enabled'
    end
  end

  # messages expire independently of hashed index. we update index
  # and remove nonces for messages that already expired
  def _compact
    nonces = rds.hkeys hpk_tag
    # select all nonces that no longer have corresponding message stored
    toDel = nonces.select { |n| not rds.exists? msg_tag n }

    # delete all these nonces from hash index
    unless toDel.empty?
      _resetCount()
      runRedisTransaction(hpk_tag, @hpk, 'compact') do |_file_info, rds_transaction|
        toDel.each { |n| rds_transaction.hdel hpk_tag, n }
      end
    end
  end

  def _resetCount()
    @lastCount = nil
  end

end
