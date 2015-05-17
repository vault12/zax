require "base64"
require "key_params"

module Utils
  include KeyParams

  # Double hash function
  def h2(msg)
    RbNaCl::Hash.sha256 RbNaCl::Hash.sha256(msg)+msg
  end

  def xor_str(str1,str2)
    str1.bytes.zip(str2.bytes).map { |a,b| a^b }.pack("C*")
  end

  def b64enc(str)
    Base64.strict_encode64 str
  end

  def b64dec(str)
    Base64.strict_decode64 str
  end
end