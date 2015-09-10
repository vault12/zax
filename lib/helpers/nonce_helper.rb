require "utils"

# --- HPK checks --- 
module NonceHelper
  include Utils

  protected
  # 8 byte timestamp in 24 byte nonce
  # MSB first; first 4 bytes will be 0 for a while.
  def _get_nonce_time(n)
    nb = n.unpack("C*")[0,8]
    nb.each_index.reduce { |s,i| s + nb[i]*256**(7-i) }
  end

  # check nonce to be withing valid expiration window
  def _check_nonce(nonce)
    # TODO: keep nonces in 5 min memcached to prevent replay attack
    raise "Bad nonce: #{dump nonce}" unless nonce and nonce.length==NONCE_LEN
    nt = _get_nonce_time nonce
    if (Time.now.to_i-nt).abs > Rails.configuration.x.relay.max_nonce_diff
      fail "Nonce timestamp #{nt} delta #{Time.now.to_i-nt}"
    end
    return nonce
  end

  def _make_nonce(tnow = Time.now.to_i)
    nonce = (rand_bytes 24).unpack "C24"

    timestamp = (Math.log(tnow)/Math.log(256)).floor.downto(0).map do
      |i| (tnow / 256**i) % 256
    end
    blank = Array.new(8) { 0 } # zero as 8 byte integer

    # 64 bit timestamp, MSB first
    blank[-timestamp.length,timestamp.length] = timestamp

    # Nonce first 8 bytes are timestamp
    nonce[0,blank.length] = blank
    return nonce.pack("C*")
  end
end