require "base64"
require "key_params"

module Utils
  include KeyParams

  def h2(msg)
    raise "util: can not h2 nil" if msg.nil?
    (RbNaCl::Hash.sha256 RbNaCl::Hash.sha256(msg)+msg)
  end

  def rand_bytes(count)
    RbNaCl::Random.random_bytes(count)
  end

  def xor_str(str1,str2)
    raise "util: can not xor_str nil" if str1.nil? or str2.nil?
    str1.bytes.zip(str2.bytes).map { |a,b| a^b }.pack("C*")
  end

  def b64enc(str)
    raise "util: can not b64enc nil" if str.nil?
    Base64.strict_encode64 str
  end

  def b64dec(str)
    raise "util: can not b64dec nil" if str.nil?
    Base64.strict_decode64 str
  end

  def toHex(s)
    s.bytes.map {|x| x.to_s(16)}.join
  end

  def dump(obj)
    return 'nil' unless obj
    obj.to_s[0...8].dump  # hide most of the key for log dumps
  end

  def dumpHex(obj)
    return 'nil' unless obj
    (toHex obj.to_s)[0...8]  # hide most of the key for log dumps
  end

  def logger
    Rails.logger
  end

  def concat_str(str1,str2)
    raise "util: can not concat_str nil" if str1.nil? or str2.nil?
    str1+str2
  end
end
