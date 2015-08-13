require 'json'

class Mailbox
  include Utils
  attr_reader :hpk

  def initialize(hpk)
    raise "Wrong HPK in mailbox.ctor()" unless hpk and hpk.length==HPK_LEN
    @tmout = Rails.configuration.x.relay.mailbox_timeout
    @hpk = b64enc hpk
    @index = {}
  end

  def count()
    redisc.llen("mbx_#{@hpk}")
  end

  # --- Store crypto records ---

  # Records are always added at the end of the list with rpush
  def store(from, nonce, data)
    raise "Bad call mailbox.store()" unless data and
      from and from.length==HPK_LEN

    b64_from = b64enc from
    b64_nonce = b64enc nonce
    b64_data = b64enc data

    item = {
      from: b64_from,
      nonce: b64_nonce,
      data: b64_data,
      time: Time.new.to_s
    }

    redisc.rpush("mbx_#{@hpk}",item.to_json)
    redisc.expire("mbx_#{@hpk}",@tmout)
    return item
  end

  def read(idx)
    item_in = redisc.lindex("mbx_#{@hpk}",idx)
    msg = JSON.parse(item_in.to_s)

    from = b64dec msg["from"]
    nonce = b64dec msg["nonce"]
    data = b64dec msg["data"]
    time = msg["time"]

    item = {
      from: from,
      nonce: nonce,
      data: data,
      time: time
    }
  end

  def read_all(start = 0, size = count.to_i - start)
    a = []
    for i in (start...start+size)
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

  def idx_by_id(id)
    return @index[id] if @index[id]
    for i in (0...count.to_i)
      item = self.read i
      next unless item
      chkdel = b64enc item[:nonce]
      @index[chkdel] = i
      if chkdel.eql?(id)
        return i
      end
    end
    nil
  end

  # --- Delete crypto records ---
  def delete(idx)
    item = redisc.lindex("mbx_#{@hpk}",idx)
    redisc.lrem("mbx_#{@hpk}",0,item)
  end

  def delete_by_id(id)
    hit = idx_by_id(id)
    unless hit.nil?
      delete hit
    end
  end

  private

  def redisc
    Redis.current
  end
end
