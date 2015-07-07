class Mailbox
  include Utils
  attr_reader :hpk, :top

  def self.count(hpk)
    Mailbox.new(hpk).top
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
  def store(from, data)
    raise "Bad call mailbox.store()" unless data and
      from and from.length==HPK_LEN
    item = {
      # Something resonably unique during 3-day expiration window
      id: h2(rand_bytes(16)),
      # TODO: forgot Bob's nonce!
      # recived_at: timestamp
      from: from,
      data: data
    }
    Rails.cache.write "item_#{@top}_#{@hpk}", item, expires_in: @tmout
    @top+=1
    Rails.cache.write "top_#{@hpk}", @top, expires_in: @tmout
    return item
  end

  # --- Read crypto records ---
  def read(idx)
    Rails.cache.read "item_#{idx}_#{@hpk}"
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