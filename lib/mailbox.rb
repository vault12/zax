class Mailbox
  TIMEOUT = Rails.configuration.x.relay.mailbox_timeout

  attr_accessor :hpk,:count

  def initialize(hpk)
    raise "Wrong HPK in mailbox.ctor()" unless hpk and hpk.length==32
    @hpk = hpk
    @count = Rails.cache.fetch("count_#{@hpk}", expires_in: TIMEOUT) { 0 }
  end

  def store(data)
    raise "No data in mailbox.store()" unless data
    Rails.cache.write("data_#{@count}_#{@hpk}",data,expires_in: TIMEOUT)
    @count+=1
    Rails.cache.write("count_#{@hpk}",@count,expires_in: TIMEOUT)
  end

  def read(idx)
    Rails.cache.read "data_#{idx}_#{@hpk}"
  end

  def read_all
    a = []
    for i in (0..@count-1)
      data = self.read i
      yield data if block_given?
      a.push data
    end
    return a
  end

end