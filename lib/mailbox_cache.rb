class MailboxCache
  include Utils
  attr_reader :hpk, :top

  def self.count(hpk)
    MailboxCache.new(hpk).top
  end

  def initialize(hpk)
    raise "Wrong HPK in mailbox.ctor()" unless hpk and hpk.length==HPK_LEN
    @tmout = Rails.configuration.x.relay.mailbox_timeout
    @hpk = hpk
    @top = Rails.cache.fetch("top_#{@hpk}", expires_in: @tmout) { 0 }
    @index = {}
  end

  # --- Store crypto records ---

  # Records are always added at the top mark
  def store(from, nonce, data)
    raise "Bad call mailbox.store()" unless data and
      from and from.length==HPK_LEN

    b64_from = b64enc from
    b64_nonce = b64enc nonce
    b64_data = b64enc data

    item = {
      nonce: b64_nonce,
      received_at: Time.new.to_s,
      from: b64_from,
      data: b64_data
    }

    Rails.cache.write "item_#{@top}_#{@hpk}", item, expires_in: @tmout
    @top+=1
    Rails.cache.write "top_#{@hpk}", @top, expires_in: @tmout
    return item
  end

  # --- Read crypto records ---
  def read(idx)
    item_in = Rails.cache.read "item_#{idx}_#{@hpk}"

    from = b64dec item_in[:from]
    nonce = b64dec item_in[:nonce]
    data = b64dec item_in[:data]
    time = item_in[:received_at]

    item = {
      from: from,
      nonce: nonce,
      data: data,
      received_at: time
    }
  end

  def read_all(start = 0, count = @top-start)
    a = []
    for i in (start...start+count)
      item = self.read i
      next unless item
      yield item if block_given?
      a.push item
    end
    return a
  end

  def find_by_id(id)
    i = idx_by_id id
    return i ? read(i) : nil
  end

  # returns [index, item] by id
  def idx_by_id(id)
    return @index[id] if @index[id]
    for i in (0...@top)
      item = self.read i
      next unless item
      @index[item[:id]] = i
      return i if item[:id].eql?(id)
    end
    nil
  end

  # --- Delete crypto records ---
  def delete(idx)
    Rails.cache.delete "item_#{idx}_#{@hpk}"
    update_top
  end

  def delete_by_id(id)
    delete idx_by_id(id)
  end

  def update_top
    # Compact empty space on top
    ts = @top
    while @top>0 and not read(@top-1)
      @top-=1
    end
    Rails.cache.write("top_#{@hpk}",@top,expires_in: @tmout) if ts!=@top
  end

end
