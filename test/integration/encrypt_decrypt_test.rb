# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'
require 'mailbox'

class EncryptDecryptTest < ActionDispatch::IntegrationTest

  test 'encrypt and decrypt' do

    # generate alice's secret key
    @alicesk = RbNaCl::PrivateKey.generate
    # generate public key from secret key
    @alicepk = @alicesk.public_key

    # generate bob's secret key
    @bobsk = RbNaCl::PrivateKey.generate
    #generate public key from secret key
    @bobpk = @bobsk.public_key

    hpk = RbNaCl::Random.random_bytes 32
    mbx = Mailbox.new hpk
    assert_not_nil mbx.hpk
    hpkey = "mbx_#{mbx.hpk}"

    for i in (1..5)
      from = h2("#{i}")
      nonce = h2(rand_bytes(16))
      mbx.store from, nonce, "hello alice from bob #{i - 1}"
      assert_equal i, rds.hlen(hpkey) # HACK
    end

    results = mbx.read_all

    results.each do |item|
        id = item[:id]
    end

    hpkto = RbNaCl::Random.random_bytes(32)

    data = {}
    data[:hpkto] = b64enc hpkto

    nonce = _make_nonce
    # this step is critical for _encrypt_data to work
    enc_nonce = b64enc nonce
    data[:nonce] = enc_nonce

    encrypt_data = _encrypt_data nonce, data

    ciphertext = b64dec encrypt_data
    decrypt_data = _decrypt_data nonce, ciphertext
    assert_equal(data[:hpkto], decrypt_data["hpkto"])
  end

  def _encrypt_data(nonce, data)
    # send bob's public key to alice
    box = RbNaCl::Box.new(@alicepk, @bobsk)
    b64enc box.encrypt(nonce, data.to_json)
  end

  def _decrypt_data(nonce, ctext)
    box = RbNaCl::Box.new(@bobpk, @alicesk)
    d = JSON.parse box.decrypt(nonce, ctext)
  end

  # copied from response_helper.rb
  def _make_nonce(tnow = Time.now.to_i)
    nonce = (rand_bytes 24).unpack 'C24'

    timestamp = (Math.log(tnow) / Math.log(256)).floor.downto(0).map do
      |i| (tnow / 256 ** i) % 256
    end
    blank = Array.new(8){0} # zero as 8 byte integer

    # 64 bit timestamp, MSB first
    blank[-timestamp.length,timestamp.length] = timestamp

    # Nonce first 8 bytes are timestamp
    nonce[0, blank.length] = blank
    return nonce.pack('C*')
  end
end
