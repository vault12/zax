# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

require 'base64'
require 'key_params'


module Utils
  include KeyParams

  class ::String
    def to_b64
      Base64.strict_encode64 self
    end

    def from_b64
      Base64.strict_decode64 self
    end
  end

  # h2(m) = sha256(sha256(64x0 + m))
  # Zero out initial sha256 block, and double hash 0-padded message
  # http://cs.nyu.edu/~dodis/ps/h-of-h.pdf
  def h2(msg)
    fail Errors::ReportError.new self, msg: 'util: can not h2 nil' if msg.nil?
    RbNaCl::Hash.sha256 RbNaCl::Hash.sha256 "\0" * 64 + msg
  end

  def rand_bytes(count)
    RbNaCl::Random.random_bytes(count)
  end

  def rand_str(min, rnd_size =0)
    rand_bytes(min + rand(rnd_size)).to_b64.delete('=')
  end

  def xor_str(str1, str2)
    fail Errors::ReportError.new self, msg: 'util: can not xor_str nil' if str1.nil? or str2.nil?
    str1.bytes.zip(str2.bytes).map { |a,b| a^b }.pack('C*')
  end

  def b64enc(str)
    fail Errors::ReportError.new self, msg: 'util: can not b64enc nil' if str.nil?
    Base64.strict_encode64 str
  end

  def b64dec(str)
    fail Errors::ReportError.new self, msg: 'util: can not b64dec nil' if str.nil?
    Base64.strict_decode64 str
  end

  def toHex(s)
    s.bytes.map {|x| x.to_s(16)}.join
  end

  def dump(obj, full = false)
    return 'nil' unless obj
    d = obj.to_s
    full ? d.dump : d[0...8].dump # hide most of the key for log dumps
  end

  def dumpHex(obj, full = false)
    return 'nil' unless obj
    d = toHex obj.to_s
    full ? d : d[-8..d.length]  # hide most of the key for log dumps
  end

  def logger
    Rails.logger
  end

  def concat_str(str1, str2)
    raise ReportError.new self, msg: 'util: can not concat_str nil' if str1.nil? or str2.nil?
    str1+str2
  end

  def first_zero_bits?(byte, n)
    byte == ((byte >> n) << n)
  end

  def array_zero_bits?(arr, diff)
    rmd = diff
    for i in 0..(1 + diff / 8)
      a = arr[i]
      return true if rmd <= 0
      if rmd > 8
        rmd -= 8
        return false if a > 0
      else
        return first_zero_bits?(a, rmd)
      end
    end
    return false
  end

  # Jobs run at second 5 of a period
  def start_diff_period(period, count = 1)
    t = DateTime.now
    t + count * period.minutes - (t.minute % period).minutes - t.second.seconds + 5.seconds
  end

  def static_diff?
    period = Rails.configuration.x.relay.period
    period.nil? or period < 1
  end

  def get_diff(check_temp_diff = false)
    diff = Rails.configuration.x.relay.difficulty

    # diff throttling is dsiabled
    return diff if static_diff?

    # Temp value if difficulty just changed
    if check_temp_diff
      tdiff = $redis.get ZAX_TEMP_DIFF
      return tdiff.to_i unless tdiff.nil?
    end

    # Dynamic value from redis if set
    rdiff = $redis.get ZAX_CUR_DIFF
    return rdiff.nil? ? diff : rdiff.to_i
  end

  def set_diff(new_diff)
    unless static_diff?
      period = Rails.configuration.x.relay.period
      old_diff = get_diff(false)
      # Global setting

      ttl = start_diff_period(period, ZAX_DIFF_LENGTH).to_i - DateTime.now.to_i
      $redis.set ZAX_CUR_DIFF, new_diff, **{ ex: ttl}

      # Save old difficulty for maximum amount of time old handshake nonces will be valid
      if new_diff != old_diff
        $redis.set ZAX_TEMP_DIFF, old_diff,
          **{ ex: Rails.configuration.x.relay.max_nonce_diff.seconds.to_i + 5 }
        logger.info "#{INFO} Caching diff: #{RED}#{old_diff}#{ENDCLR} => #{RED}#{new_diff}#{ENDCLR}"
      end
    end

    # only affects current worker request
    Rails.configuration.x.relay.difficulty = new_diff
    return new_diff
  end

end
