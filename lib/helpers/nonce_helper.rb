# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'utils'
require 'errors/nonce_error'

# --- Nonce checks ---
module Helpers
  module NonceHelper
    include Utils
    include Errors

    protected

    # 8 byte timestamp in 24 byte nonce
    # MSB first; first 4 bytes will be 0 for a while.
    def _get_nonce_time(n)
      nb = n.unpack("C*")[0, 8]
      nb.each_index.reduce {|s, i| s + nb[i] * 256 ** (7 - i)}
    end

    # check nonce uniqueness within the specified expiration time window
    # if outside the expiration window, nonce will always fail the timestamp check
    # unless_exist makes check-and-record one atomic operation (the single-use
    # session key idiom): a separate read-then-write let two requests carrying
    # the same nonce both observe a miss and both pass. The conditional write
    # returns false when the nonce is already recorded — that is the replay.
    def _check_nonce_unique(nonce)
      nonce_b64 = nonce.to_b64
      unless Rails.cache.write("nonce_#{nonce_b64}", nonce_b64,
        expires_in: Rails.configuration.x.relay.nonce_timeout, unless_exist: true)
        fail NonceError.new self, {nonce: nonce_b64, reason: 'NonceReplay', msg: 'Nonce Not Unique'}
      end
    end

    # Validate nonce shape + timestamp freshness only. STATELESS — writes nothing,
    # so it is safe to run before authentication. Returns the nonce.
    def _validate_nonce(nonce)
      fail NonceError.new self, msg: "Bad nonce: #{dump nonce}" unless nonce and nonce.length == NONCE_LEN
      nt = _get_nonce_time nonce
      if (Time.now.to_i - nt).abs > Rails.configuration.x.relay.max_nonce_diff
        fail NonceError.new self, reason: 'ClockSkew', msg: "Nonce timestamp #{nt} delta #{Time.now.to_i - nt}"
      end
      return nonce
    end

    # Validate the nonce AND record it for replay protection. Because this writes
    # to the cache, callers must only reach it for an auth request —
    # CommandController defers the uniqueness write until after decrypt 
    def _check_nonce(nonce)
      _validate_nonce(nonce)
      _check_nonce_unique(nonce)
      return nonce
    end

    # Create new NaCl nonce with timestamp. First 8 bytes is timestamp,
    # the following 16 bytes are random.
    def _make_nonce(tnow = Time.now.to_i)
      nonce = (rand_bytes NONCE_LEN).unpack "C#{NONCE_LEN}"

      timestamp = (Math.log(tnow)/Math.log(256)).floor.downto(0).map do
        |i| (tnow / 256 ** i) % 256
      end
      blank = Array.new(8) {0} # zero as 8 byte integer

      # 64 bit timestamp, MSB first
      blank[-timestamp.length, timestamp.length] = timestamp

      # Nonce first 8 bytes are timestamp
      nonce[0, blank.length] = blank
      return nonce.pack("C*")
    end
  end
end
