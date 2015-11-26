# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

require 'base64'
require 'key_params'

module Utils
  include KeyParams

  # h2(m) = sha256(sha256(32x0 + m))
  # Zero out initial sha256 block, and double hash 0-padded message
  # http://cs.nyu.edu/~dodis/ps/h-of-h.pdf
  def h2(msg)
    fail ReportError.new self, msg: 'util: can not h2 nil' if msg.nil?
    RbNaCl::Hash.sha256 RbNaCl::Hash.sha256 "\0" * 32 + msg
  end

  def rand_bytes(count)
    RbNaCl::Random.random_bytes(count)
  end

  def xor_str(str1, str2)
    fail ReportError.new self, msg: 'util: can not xor_str nil' if str1.nil? or str2.nil?
    str1.bytes.zip(str2.bytes).map { |a,b| a^b }.pack('C*')
  end

  def b64enc(str)
    fail ReportError.new self, msg: 'util: can not b64enc nil' if str.nil?
    Base64.strict_encode64 str
  end

  def b64dec(str)
    fail ReportError.new self, msg: 'util: can not b64dec nil' if str.nil?
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

end
