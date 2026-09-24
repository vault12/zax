# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

class CommandControllerFileTest < ActionDispatch::IntegrationTest

  test 'file commands: start/status/upload' do
    ### request uploadID to upload files by chunks, check status
    ### and download

    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk

    to_key = RbNaCl::PrivateKey.generate
    to_hpk = h2(to_key.public_key)

    # === start file upload: missing required params
    [ { cmd: 'startFileUpload' },
      { cmd: 'startFileUpload', file_size: 20100, metadata: {} },
      { cmd: 'startFileUpload', to: 20100, metadata: {} },
      { cmd: 'startFileUpload', to: 20100, file_size: 20100, metadata: {} }
    ].each do |d|
      n = _make_nonce
      _fail_response _post '/command', hpk, n, _client_encrypt_data(n, d)
    end

    ### === Start File Upload correct request ===
    msg_nonce = rand_bytes(24).to_b64
    msg_data = {
      cmd: 'startFileUpload',
      to: to_hpk.to_b64,
      file_size: 20100,
      metadata: {
        ctext: 'session encrypted payload per File API',
        nonce: msg_nonce
      }
    }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    rdata = decrypt_2_lines _check_response _success_response
    assert_not_nil rdata
    assert_not_nil rdata[:uploadID]
    assert_not_nil rdata[:max_chunk_size]
    assert_not_nil rdata[:storage_token]
    test_file_id = rdata[:uploadID]

    ### === Status of message => hpk_to about uploading file
    n = _make_nonce
    data = { cmd: 'messageStatus', token: rdata[:storage_token] }
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    r = _success_response
    assert_operator r.to_i, :>, 0 # message TTL is above 0

    ### === File status of uploading file from sender
    n = _make_nonce
    data = { cmd: 'fileStatus', uploadID: test_file_id }
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    rdata1 = decrypt_2_lines _check_response _success_response
    assert_not_nil rdata1
    assert_equal 0, rdata1[:bytes_stored]
    assert_equal "START", rdata1[:status]

    ### === File status of uploading file from receiver
    _setup_keys to_hpk
    n = _make_nonce
    data = { cmd: 'fileStatus', uploadID: test_file_id}
    _post '/command', to_hpk, n, _client_encrypt_data(n, data)
    rdata2 = decrypt_2_lines _check_response _success_response
    assert_not_nil rdata2
    assert_equal 0, rdata2[:bytes_stored]
    assert_equal "START", rdata2[:status]

    # It the same file
    assert_equal rdata1,rdata2

    # Back to main hpk
    _setup_keys hpk

    # === fileStatus: No uploadID
    n = _make_nonce
    data = { cmd: 'fileStatus' }
    _fail_response _post '/command', hpk, n, _client_encrypt_data(n, data)

    # === No file on relay
    n = _make_nonce
    data = { cmd: 'fileStatus', uploadID: rand_bytes(32).to_b64}
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    rdata = decrypt_2_lines _check_response _success_response
    assert_not_nil rdata
    assert_equal rdata[:bytes_stored],0
    assert_equal rdata[:status],"NOT_FOUND"

    # === Upload file chunk: missing required params
    [ { cmd: 'uploadFileChunk' },
      { cmd: 'uploadFileChunk', uploadID: test_file_id  },
      { cmd: 'uploadFileChunk', part: 0  },
      { cmd: 'uploadFileChunk', uploadID: test_file_id, part: 0 }
    ].each do |d|
       n = _make_nonce
      _fail_response _post '/command', hpk, n, _client_encrypt_data(n, d), "ZmlsZWRhdGEK"
    end

    ### === Upload file chunks
    parts = (0...5)
    chunk = 256
    file_parts = []

    # Try sequentioal upload first
    for i in parts
      file_parts[i] = rand_bytes chunk
      data = {
        cmd: 'uploadFileChunk',
        uploadID: test_file_id,
        part: i,
        nonce: _make_nonce.to_b64,
      }

      # Second chunk, check first one is stored
      if (i == 1)
        tmp_data = { cmd: 'fileStatus', uploadID: test_file_id}
        n = _make_nonce
        _post '/command', hpk, n, _client_encrypt_data(n, tmp_data)
        tmp_rdata = decrypt_2_lines _check_response _success_response
        assert_not_nil tmp_rdata
        assert_equal "UPLOADING", tmp_rdata[:status]
        assert_equal chunk, tmp_rdata[:bytes_stored]
      end

      # Last chunk
      if (i == parts.last - 1)
        data[:last_chunk] = true
      end

      # Upload current chunk
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, data), file_parts[i]
      _success_response
    end

    # === Lets check what we uploaded
    data = { cmd: 'fileStatus', uploadID: test_file_id }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    rdata = decrypt_2_lines _check_response _success_response
    assert_not_nil rdata
    assert_equal parts.size*chunk, rdata[:bytes_stored]
    assert_equal "COMPLETE", rdata[:status]

    ### Download

    # === Download: missing required params
    [ { cmd: 'downloadFileChunk' },
      { cmd: 'downloadFileChunk', uploadID: test_file_id  },
      { cmd: 'downloadFileChunk', part: 0  }
    ].each do |d|
       n = _make_nonce
      _fail_response _post '/command', hpk, n, _client_encrypt_data(n, d)
    end

    download = []
    for i in parts
      data = { cmd: 'downloadFileChunk',
               uploadID: test_file_id,
               part: i }
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, data)
      data, file  = decrypt_3_lines _check_response _success_response

      assert_not_nil data
      assert_not_nil file
      download[i] = file.from_b64
      assert_equal chunk, download[i].length
    end

    # It is the file we sent
    for i in parts
      assert_equal file_parts[i],download[i]
    end

    ## Delete
    # === Delete: missing required params
    [ { cmd: 'deleteFile' } ].each do |d|
       n = _make_nonce
      _fail_response _post '/command', hpk, n, _client_encrypt_data(n, d)
    end

    data = { cmd: 'deleteFile',
             uploadID: test_file_id }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    data = decrypt_2_lines _check_response _success_response
    assert_not_nil data
    assert_equal "OK", data[:status]

    # === File is gone
    data = { cmd: 'fileStatus', uploadID: test_file_id}
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    rdata = decrypt_2_lines _check_response _success_response
    assert_not_nil rdata
    assert_equal 0, rdata[:bytes_stored]
    assert_equal "NOT_FOUND", rdata[:status]
  end

  test 'file commands: race conditions' do
    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk

    to_key = RbNaCl::PrivateKey.generate
    to_hpk = h2(to_key.public_key)

    ### === Start File Upload ===
    msg_nonce = rand_bytes(24).to_b64
    msg_data = {
      cmd: 'startFileUpload',
      to: to_hpk.to_b64,
      file_size: 20100,
      metadata: {
        ctext: 'session encrypted payload per File API',
        nonce: msg_nonce
      }
    }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    rdata = decrypt_2_lines _check_response _success_response
    assert_not_nil rdata
    assert_not_nil rdata[:uploadID]
    assert_not_nil rdata[:max_chunk_size]
    assert_not_nil rdata[:storage_token]
    test_file_id = rdata[:uploadID]

    ### === Upload file chunks
    parts = (0...5)
    chunk = 256
    file_parts = []

    # Upload all parts at once and let relay
    # resolve race conditions to get all parts
    start_flag = false
    threads = parts.map do |i|
      Thread.new do
        true while not start_flag

        file_parts[i] = rand_bytes chunk
        data = {
          cmd: 'uploadFileChunk',
          uploadID: test_file_id,
          part: i,
          nonce: _make_nonce.to_b64,
        }

        # Last chunk
        if (i == parts.last - 1)
          data[:last_chunk] = true
        end

        # Upload current chunk
        n = _make_nonce
        _post '/command', hpk, n, _client_encrypt_data(n, data), file_parts[i]
        _success_response
      end
    end

    # Begin all threads
    start_flag = true
    threads.each(&:join)
    sleep 0.3

    # === Lets check what we uploaded
    data = { cmd: 'fileStatus', uploadID: test_file_id }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    rdata = decrypt_2_lines _check_response _success_response
    assert_not_nil rdata
    assert_equal parts.size*chunk, rdata[:bytes_stored]
    assert_equal "COMPLETE", rdata[:status]

    ### Download
    download = []
    for i in parts
      data = { cmd: 'downloadFileChunk',
               uploadID: test_file_id,
               part: i }
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, data)
      data, file = decrypt_3_lines _check_response _success_response

      assert_not_nil data
      download[i] = file.from_b64
      assert_equal chunk, download[i].length
    end

    # It is the file we sent
    for i in parts
      assert_equal file_parts[i],download[i]
    end

    ## Delete
    data = { cmd: 'deleteFile',
             uploadID: test_file_id }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    data = decrypt_2_lines _check_response _success_response
    assert_not_nil data
    assert_equal "OK", data[:status]

    # === File is gone
    data = { cmd: 'fileStatus', uploadID: test_file_id}
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    rdata = decrypt_2_lines _check_response _success_response
    assert_not_nil rdata
    assert_equal 0, rdata[:bytes_stored]
    assert_equal "NOT_FOUND", rdata[:status]
  end

  # concurrent uploadFileChunk requests must not push a file past its
  # declared file_size. the authoritative check now runs inside the transaction.
  test 'file commands: concurrent chunks cannot overrun declared file_size' do
    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk
    to_hpk = h2(RbNaCl::PrivateKey.generate.public_key)

    overhead  = FileManager.new.per_chunk_overhead
    chunk     = 2048
    n_chunks  = 5
    file_size = 4300 # 5 parts allowed; with 2048B chunks + overhead only ~2 fit

    msg_nonce = rand_bytes(24).to_b64
    start = { cmd: 'startFileUpload', to: to_hpk.to_b64, file_size: file_size,
              metadata: { ctext: 'x', nonce: msg_nonce } }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, start)
    uploadID = (decrypt_2_lines _check_response _success_response)[:uploadID]

    # Fire all chunks at once, distinct part indices, to force the race.
    start_flag = false
    threads = (0...n_chunks).map do |i|
      Thread.new do
        true while not start_flag
        data = { cmd: 'uploadFileChunk', uploadID: uploadID, part: i, nonce: _make_nonce.to_b64 }
        nn = _make_nonce
        # Over-cap chunks are rejected (400); the shared integration `response`
        # is unreliable across threads, so we assert only on the final state below.
        _post '/command', hpk, nn, _client_encrypt_data(nn, data), rand_bytes(chunk) rescue nil
      end
    end
    start_flag = true
    threads.each(&:join)
    sleep 0.3

    # Authoritative final state, read sequentially.
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, { cmd: 'fileStatus', uploadID: uploadID })
    st = decrypt_2_lines _check_response _success_response

    # The hard invariant: stored bytes never exceed the declared cap + overhead.
    # (fileStatus strips :parts; :total_chunks is the stored part count.)
    assert_operator st[:bytes_stored], :<=, file_size + st[:total_chunks] * overhead,
      'stored bytes must stay within declared file_size (pre-fix this overran)'
    # And the overrun really was prevented — not every racing chunk landed.
    assert_operator st[:bytes_stored], :<, n_chunks * chunk,
      'concurrent chunks must not all commit past the cap'
  end

  test 'file commands: commands fail if file storage is disabled' do
    save = Rails.configuration.x.relay.file_store[:enabled]
    Rails.configuration.x.relay.file_store[:enabled] = false

    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk

    to_key = RbNaCl::PrivateKey.generate
    to_hpk = h2(to_key.public_key)

    ### === Start File Upload ===
    msg_nonce = rand_bytes(24).to_b64
    msg_data = {
      cmd: 'startFileUpload',
      to: to_hpk.to_b64,
      file_size: 20100,
      metadata: {
        ctext: 'session encrypted payload per File API',
        nonce: msg_nonce
      }
    }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    assert_response :method_not_allowed
    assert_empty response.body

    data = { cmd: 'fileStatus', uploadID: rand_bytes(32).to_b64 }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data)
    assert_response :method_not_allowed
    assert_empty response.body

    # Regular messaging works as usual
    msg_data = {
      cmd: 'upload',
      to: to_hpk.to_b64,
      payload: {
        ctext: 'hello world 0',
        nonce: msg_nonce
      }
    }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    msg_token = b64dec _success_response # 32 byte storage token for the message
    assert_equal(32, msg_token.length)

    Rails.configuration.x.relay.file_store[:enabled] = save
  end

  # Regression: an out-of-range part index must be rejected (400),
  # never used as a raw Array index (which would materialise a huge sparse Array).
  test 'file commands: out-of-range part index is rejected' do
    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk

    to_key = RbNaCl::PrivateKey.generate
    to_hpk = h2(to_key.public_key)

    file_size = 20100
    msg_nonce = rand_bytes(24).to_b64
    msg_data = {
      cmd: 'startFileUpload',
      to: to_hpk.to_b64,
      file_size: file_size,
      metadata: { ctext: 'session encrypted payload per File API', nonce: msg_nonce }
    }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    rdata = decrypt_2_lines _check_response _success_response
    test_file_id = rdata[:uploadID]

    # The part bound is derived from the declared size: ceil(file_size /
    # MIN_BYTES_PER_PART) parts. 20100 bytes -> 20 parts, indices 0..19.
    allowed_parts = (file_size + KeyParams::MIN_BYTES_PER_PART - 1) / KeyParams::MIN_BYTES_PER_PART
    assert_equal 20, allowed_parts

    # A part index past the file's own bound is rejected, both on upload
    # (the memory-exhaustion path) and on download.
    huge_part = 100_000_000
    up = { cmd: 'uploadFileChunk', uploadID: test_file_id, part: huge_part, nonce: _make_nonce.to_b64 }
    n = _make_nonce
    _fail_response _post '/command', hpk, n, _client_encrypt_data(n, up), rand_bytes(256)

    dn = { cmd: 'downloadFileChunk', uploadID: test_file_id, part: huge_part }
    n = _make_nonce
    _fail_response _post '/command', hpk, n, _client_encrypt_data(n, dn)

    # A part exactly at the boundary (== allowed_parts) is rejected; the last
    # valid index (allowed_parts - 1) is accepted.
    n = _make_nonce
    _fail_response _post '/command', hpk, n,
      _client_encrypt_data(n, { cmd: 'uploadFileChunk', uploadID: test_file_id, part: allowed_parts, nonce: _make_nonce.to_b64 }), rand_bytes(256)

    n = _make_nonce
    _post '/command', hpk, n,
      _client_encrypt_data(n, { cmd: 'uploadFileChunk', uploadID: test_file_id, part: allowed_parts - 1, nonce: _make_nonce.to_b64 }), rand_bytes(256)
    _success_response
  end

  # Regression: re-uploading the same part must not inflate bytes_stored
  # or total_chunks — one copy is stored on disk regardless of re-sends.
  test 'file commands: re-uploading a part does not inflate accounting' do
    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk

    to_key = RbNaCl::PrivateKey.generate
    to_hpk = h2(to_key.public_key)

    msg_nonce = rand_bytes(24).to_b64
    msg_data = {
      cmd: 'startFileUpload',
      to: to_hpk.to_b64,
      file_size: 20100,
      metadata: { ctext: 'session encrypted payload per File API', nonce: msg_nonce }
    }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    rdata = decrypt_2_lines _check_response _success_response
    test_file_id = rdata[:uploadID]

    upload_part = lambda do |part, size|
      data = { cmd: 'uploadFileChunk', uploadID: test_file_id, part: part, nonce: _make_nonce.to_b64 }
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, data), rand_bytes(size)
      _success_response
    end

    file_status = lambda do
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, { cmd: 'fileStatus', uploadID: test_file_id })
      decrypt_2_lines _check_response _success_response
    end

    # Two distinct parts of 256 bytes each
    upload_part.call(0, 256)
    upload_part.call(1, 256)
    st = file_status.call
    assert_equal 512, st[:bytes_stored]
    assert_equal 2, st[:total_chunks]

    # Re-upload part 0 at the same size: no change to accounting
    upload_part.call(0, 256)
    st = file_status.call
    assert_equal 512, st[:bytes_stored]
    assert_equal 2, st[:total_chunks]

    # Re-upload part 0 at a different size: only the delta is applied
    upload_part.call(0, 300)
    st = file_status.call
    assert_equal 556, st[:bytes_stored] # 300 + 256
    assert_equal 2, st[:total_chunks]
  end

  # Per-file cap: a chunk that would push the stored total past the
  # declared file_size is rejected; storage stops growing once the cap is hit.
  test 'file commands: upload exceeding declared file_size is rejected' do
    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk

    to_key = RbNaCl::PrivateKey.generate
    to_hpk = h2(to_key.public_key)

    overhead = Rails.configuration.x.relay.file_store[:per_chunk_overhead]

    start_upload = lambda do |file_size|
      msg_nonce = rand_bytes(24).to_b64
      msg_data = {
        cmd: 'startFileUpload', to: to_hpk.to_b64, file_size: file_size,
        metadata: { ctext: 'session encrypted payload per File API', nonce: msg_nonce }
      }
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
      (decrypt_2_lines _check_response _success_response)[:uploadID]
    end
    upload_part = lambda do |uid, part, size|
      data = { cmd: 'uploadFileChunk', uploadID: uid, part: part, nonce: _make_nonce.to_b64 }
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, data), rand_bytes(size)
    end
    file_status = lambda do |uid|
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, { cmd: 'fileStatus', uploadID: uid })
      decrypt_2_lines _check_response _success_response
    end

    # Ciphertext overhead: like glow.ts, the client declares the plaintext size
    # but uploads encrypted chunks, so bytes_stored legitimately exceeds file_size
    # by per-chunk overhead. This must be allowed. (2100 bytes allow 3 part
    # slots; 3 x 800 = 2400 stored fits under 2100 + 3 x overhead.)
    uid = start_upload.call(2100)
    3.times { |i| upload_part.call(uid, i, 800); _success_response } # 2400 stored > 2100 declared
    st = file_status.call(uid)
    assert_equal 2400, st[:bytes_stored]
    assert_operator st[:bytes_stored], :>, 2100 # over the plaintext declaration, still accepted

    # Gross overshoot: a chunk far past file_size + per-chunk overhead is rejected,
    # and the stored total is unchanged.
    uid2 = start_upload.call(100)
    _fail_response upload_part.call(uid2, 0, 100 + overhead + 500)
    assert_equal 0, file_status.call(uid2)[:bytes_stored]

    # A chunk within file_size + overhead is accepted.
    upload_part.call(uid2, 0, 100 + overhead - 10); _success_response
    assert_operator file_status.call(uid2)[:bytes_stored], :>, 0
  end

  # per-sender storage quota. Once the declared sizes of
  # a sender's live files reach max_storage_bytes, startFileUpload is rejected.
  # Deleting a file or letting it expire returns its quota.
  test 'file commands: per-sender storage quota' do
    save = Rails.configuration.x.relay.file_store[:max_storage_bytes]
    save_max_file = Rails.configuration.x.relay.file_store[:max_file_size]
    # keep max_file_size <= the shrunken quota or FileManager refuses to boot
    Rails.configuration.x.relay.file_store[:max_storage_bytes] = 1000
    Rails.configuration.x.relay.file_store[:max_file_size] = 1000

    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk

    to_key = RbNaCl::PrivateKey.generate
    to_hpk = h2(to_key.public_key)

    start_upload = lambda do |file_size|
      msg_data = {
        cmd: 'startFileUpload', to: to_hpk.to_b64, file_size: file_size,
        metadata: { ctext: 'session encrypted payload per File API', nonce: rand_bytes(24).to_b64 }
      }
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    end

    # 600 of 1000 quota used
    start_upload.call(600)
    uid1 = (decrypt_2_lines _check_response _success_response)[:uploadID]

    # Another 600 would exceed the quota => rejected, and the reason is
    # deliberately named to the sender (unlike generic protocol failures)
    _fail_response start_upload.call(600)
    assert_equal 'Sender storage quota exceeded', response.headers['X-Error-Details']

    # 300 still fits (900/1000)
    start_upload.call(300)
    uid2 = (decrypt_2_lines _check_response _success_response)[:uploadID]

    # deleteFile returns its quota: drop the 600-byte file and 600 fits again
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, { cmd: 'deleteFile', uploadID: uid1 })
    _success_response
    start_upload.call(600)
    assert_not_nil (decrypt_2_lines _check_response _success_response)[:uploadID]

    # Back at 900/1000 => 200 more is rejected
    _fail_response start_upload.call(200)

    # Expiry returns quota too: kill uid2's tracking key (what Redis TTL
    # expiration does) and the freed 300 bytes admit the 200-byte file
    fm = FileManager.new
    storage_name = fm.storage_name_from_id fm.storage_from_upload(uid2.from_b64)
    $redis.del "#{STORAGE_PREFIX}#{storage_name}"
    start_upload.call(200)
    assert_not_nil (decrypt_2_lines _check_response _success_response)[:uploadID]
  ensure
    Rails.configuration.x.relay.file_store[:max_storage_bytes] = save
    Rails.configuration.x.relay.file_store[:max_file_size] = save_max_file
  end

  # Stalled-upload sweep: an upload that never completed stops holding the
  # sender's quota once it is older than stalled_upload_expiration. A COMPLETE
  # file awaiting download and a young incomplete upload are untouched.
  test 'file commands: stalled uploads are reaped and return quota' do
    save = Rails.configuration.x.relay.file_store[:max_storage_bytes]
    save_max_file = Rails.configuration.x.relay.file_store[:max_file_size]
    # keep max_file_size <= the shrunken quota or FileManager refuses to boot
    Rails.configuration.x.relay.file_store[:max_storage_bytes] = 1000
    Rails.configuration.x.relay.file_store[:max_file_size] = 1000

    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk
    to_hpk = h2(RbNaCl::PrivateKey.generate.public_key)

    start_upload = lambda do |file_size|
      msg_data = {
        cmd: 'startFileUpload', to: to_hpk.to_b64, file_size: file_size,
        metadata: { ctext: 'session encrypted payload per File API', nonce: rand_bytes(24).to_b64 }
      }
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
      (decrypt_2_lines _check_response _success_response)[:uploadID]
    end

    fm = FileManager.new
    tag = lambda { |uid| "#{STORAGE_PREFIX}#{fm.storage_name_from_id(fm.storage_from_upload(uid.from_b64))}" }
    lifetime = Rails.configuration.x.relay.file_store[:files_expiration]
    threshold = Rails.configuration.x.relay.file_store[:stalled_upload_expiration]
    # what Redis TTL decay does over (threshold + 60) seconds, instantly
    age = lambda { |uid| $redis.expire tag.call(uid), lifetime - threshold - 60 }

    # stalled: never completed, will be aged past the threshold
    uid_stalled = start_upload.call(600)
    # completed: last chunk landed, equally old
    uid_done = start_upload.call(200)
    data = { cmd: 'uploadFileChunk', uploadID: uid_done, part: 0, nonce: _make_nonce.to_b64, last_chunk: true }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, data), rand_bytes(200)
    _success_response
    # fresh: never completed but not old enough
    uid_fresh = start_upload.call(100)

    age.call(uid_stalled)
    age.call(uid_done)

    fm.delete_stalled_uploads

    assert_not $redis.exists?(tag.call(uid_stalled)), 'stalled upload must be reaped'
    assert $redis.exists?(tag.call(uid_done)), 'a COMPLETE file awaiting download must survive'
    assert $redis.exists?(tag.call(uid_fresh)), 'a young incomplete upload must survive'

    # the reaped declaration returns its bytes: 300 of 1000 used, 600 fits again
    assert_not_nil start_upload.call(600)
  ensure
    Rails.configuration.x.relay.file_store[:max_storage_bytes] = save
    Rails.configuration.x.relay.file_store[:max_file_size] = save_max_file
  end

  # Companion to the transactional stalled reap: a last chunk completing a
  # file whose tracking key the sweep already deleted must NOT resurrect the
  # key. A plain SET+KEEPTTL on a missing key recreates it with no TTL —
  # immortal, invisible to the sweeps (already SREMed from the tracked set),
  # and holding the sender's quota until an explicit deleteFile. (The true
  # mid-transaction interleaving can't be reproduced deterministically; like
  # the deleteFile test below, this asserts the resulting invariant.)
  test 'mark_file_complete does not resurrect a reaped tracking key' do
    mbx = Mailbox.new b64enc(h2(rand_bytes(16)))
    name = "zax_test_no_resurrect_#{rand_bytes(6).to_b64}"
    tag = "#{STORAGE_PREFIX}#{name}"
    $redis.del tag # the sweep reaped it between the upload's read and MULTI
    $redis_pool.with { |conn| conn.multi { |t| mbx.mark_file_complete name, t } }
    assert_not $redis.exists?(tag), 'SET XX must not resurrect a reaped tracking key'
  ensure
    $redis.del tag if tag
  end

  # deleteFile removes the file index transactionally, and an upload
  # that lands after the delete must NOT resurrect the file_info. (The true
  # mid-transaction race can't be reproduced deterministically over HTTP; this
  # asserts the resulting invariant — no resurrection — plus that the index
  # entries are actually cleared.)
  test 'deleteFile is not resurrected by a later chunk upload' do
    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk
    to_hpk = h2(RbNaCl::PrivateKey.generate.public_key)

    fm = FileManager.new
    msg = { cmd: 'startFileUpload', to: to_hpk.to_b64, file_size: 500,
            metadata: { ctext: 'file summary', nonce: rand_bytes(24).to_b64 } }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg)
    uid = (decrypt_2_lines _check_response _success_response)[:uploadID]
    sid = fm.storage_from_upload(uid.from_b64).to_b64
    idx_to   = "file_idx_to_#{to_hpk.to_b64}"
    idx_from = "file_idx_from_#{hpk.to_b64}"

    upload = lambda do |part|
      d = { cmd: 'uploadFileChunk', uploadID: uid, part: part, nonce: _make_nonce.to_b64 }
      m = _make_nonce
      _post '/command', hpk, m, _client_encrypt_data(m, d), rand_bytes(200)
    end

    upload.call(0); _success_response
    assert $redis.hexists(idx_to, sid), 'file indexed after first chunk'

    # Delete the file
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, { cmd: 'deleteFile', uploadID: uid })
    _success_response
    assert_not $redis.hexists(idx_to, sid),   'to-index entry cleared by delete'
    assert_not $redis.hexists(idx_from, sid), 'from-index entry cleared by delete'

    # A chunk arriving after the delete must not recreate the file_info
    upload.call(1)
    st = decrypt_2_lines _check_response _success_response
    assert_equal 'NOT_FOUND', st[:status]
    assert_not $redis.hexists(idx_to, sid),   'to-index not resurrected'
    assert_not $redis.hexists(idx_from, sid), 'from-index not resurrected'
  end

  # only the sender (hpk_from) may write chunks. The recipient holds
  # the uploadID (to download) but must not be able to overwrite chunks or
  # flip status. Download/delete stay allowed from either side.
  test 'only the sender can upload chunks' do
    sender_key = RbNaCl::PrivateKey.generate
    hpk = h2(sender_key.public_key)
    _setup_keys hpk

    recv_key = RbNaCl::PrivateKey.generate
    to_hpk = h2(recv_key.public_key)

    # Sender starts the upload and learns the uploadID
    msg_data = { cmd: 'startFileUpload', to: to_hpk.to_b64, file_size: 500,
                 metadata: { ctext: 'file summary', nonce: rand_bytes(24).to_b64 } }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    uid = (decrypt_2_lines _check_response _success_response)[:uploadID]

    chunk = lambda do |for_hpk|
      d = { cmd: 'uploadFileChunk', uploadID: uid, part: 0, nonce: _make_nonce.to_b64 }
      m = _make_nonce
      _post '/command', for_hpk, m, _client_encrypt_data(m, d), rand_bytes(200)
    end

    # Sender can write a chunk
    chunk.call(hpk)
    _success_response

    # Recipient holds the same uploadID but must NOT be able to write
    _setup_keys to_hpk
    chunk.call(to_hpk)
    _fail_response :bad_request

    # ...and the sender's stored data is untouched (still one 200-byte part)
    _setup_keys hpk
    m = _make_nonce
    _post '/command', hpk, m, _client_encrypt_data(m, { cmd: 'fileStatus', uploadID: uid })
    st = decrypt_2_lines _check_response _success_response
    assert_equal 200, st[:bytes_stored]
    assert_equal 1, st[:total_chunks]

    # Recipient CAN still download (either side allowed)
    _setup_keys to_hpk
    m = _make_nonce
    _post '/command', to_hpk, m, _client_encrypt_data(m, { cmd: 'downloadFileChunk', uploadID: uid, part: 0 })
    data, file = decrypt_3_lines _check_response _success_response
    assert_equal 200, file.from_b64.length
  end

  # a recorded part whose chunk file is missing on disk (crash
  # window, disk loss) must yield a clean NOT_FOUND, not an ENOENT 500.
  test 'download of a missing chunk returns NOT_FOUND not server error' do
    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk
    to_hpk = h2(RbNaCl::PrivateKey.generate.public_key)

    msg_data = { cmd: 'startFileUpload', to: to_hpk.to_b64, file_size: 500,
                 metadata: { ctext: 'file summary', nonce: rand_bytes(24).to_b64 } }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
    uid = (decrypt_2_lines _check_response _success_response)[:uploadID]

    up = { cmd: 'uploadFileChunk', uploadID: uid, part: 0, nonce: _make_nonce.to_b64 }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, up), rand_bytes(256)
    _success_response

    # Simulate the inconsistency: metadata records part 0, chunk vanishes
    fm = FileManager.new
    chunk_file = "#{fm.storage_path}#{fm.storage_name_from_id(fm.storage_from_upload(uid.from_b64), 0)}"
    assert File.exist?(chunk_file), 'chunk landed on disk'
    File.delete chunk_file

    dn = { cmd: 'downloadFileChunk', uploadID: uid, part: 0 }
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, dn)
    st = decrypt_2_lines _check_response _success_response
    assert_equal 'NOT_FOUND', st[:status]
  end

  # expired files must not leave dead file_info fields in the
  # file_idx_to_/file_idx_from_ hashes — reaped on fileStatus read and on the
  # next startFileUpload write.
  test 'file index entries are reaped after file expiry' do
    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk
    to_hpk = h2(RbNaCl::PrivateKey.generate.public_key)

    fm = FileManager.new
    start_upload = lambda do
      msg_data = { cmd: 'startFileUpload', to: to_hpk.to_b64, file_size: 500,
                   metadata: { ctext: 'file summary ctext', nonce: rand_bytes(24).to_b64 } }
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, msg_data)
      (decrypt_2_lines _check_response _success_response)[:uploadID]
    end
    field_of  = ->(uid) { fm.storage_from_upload(uid.from_b64).to_b64 }
    expire    = ->(uid) { $redis.del "#{STORAGE_PREFIX}#{fm.storage_name_from_id(fm.storage_from_upload(uid.from_b64))}" }
    idx_to    = "file_idx_to_#{to_hpk.to_b64}"
    idx_from  = "file_idx_from_#{hpk.to_b64}"

    uid1 = start_upload.call
    assert $redis.hexists(idx_to, field_of[uid1])
    assert $redis.hexists(idx_from, field_of[uid1])

    # Simulate expiry (tracking key dies, as Redis TTL does), then reap-on-read:
    # fileStatus reports NOT_FOUND and drops the field from BOTH hashes
    expire[uid1]
    n = _make_nonce
    _post '/command', hpk, n, _client_encrypt_data(n, { cmd: 'fileStatus', uploadID: uid1 })
    st = decrypt_2_lines _check_response _success_response
    assert_equal 'NOT_FOUND', st[:status]
    assert_not $redis.hexists(idx_to, field_of[uid1]), 'stale entry reaped from to-index on read'
    assert_not $redis.hexists(idx_from, field_of[uid1]), 'stale entry reaped from from-index on read'

    # Reap-on-write: a dead entry is swept by the next startFileUpload
    uid2 = start_upload.call
    expire[uid2]
    uid3 = start_upload.call
    assert_not $redis.hexists(idx_to, field_of[uid2]), 'dead entry reaped from to-index on write'
    assert_not $redis.hexists(idx_from, field_of[uid2]), 'dead entry reaped from from-index on write'
    assert $redis.hexists(idx_to, field_of[uid3]), 'live entry kept'
    assert $redis.hexists(idx_from, field_of[uid3]), 'live entry kept'
  end

  # The sender quota is charged with declared file sizes, so a quota below
  # max_file_size is a misconfiguration: the largest declarable file could
  # never be declared. FileManager refuses to boot on it.
  test 'file manager refuses to boot when the quota is below max_file_size' do
    save_quota = Rails.configuration.x.relay.file_store[:max_storage_bytes]
    save_max   = Rails.configuration.x.relay.file_store[:max_file_size]
    Rails.configuration.x.relay.file_store[:max_storage_bytes] = 1000
    Rails.configuration.x.relay.file_store[:max_file_size] = 2000
    assert_raises(Errors::ConfigError) { FileManager.new }
  ensure
    Rails.configuration.x.relay.file_store[:max_storage_bytes] = save_quota
    Rails.configuration.x.relay.file_store[:max_file_size] = save_max
  end

  # The single-file size cap is config-driven (file_store[:max_file_size]),
  # not a hardcoded constant: the configured boundary is enforced inclusively
  # and nil disables the check.
  test 'file commands: declared file_size over the configured max is rejected' do
    save = Rails.configuration.x.relay.file_store[:max_file_size]
    Rails.configuration.x.relay.file_store[:max_file_size] = 1000

    key = RbNaCl::PrivateKey.generate
    hpk = h2(key.public_key)
    _setup_keys hpk
    to_hpk = h2(RbNaCl::PrivateKey.generate.public_key)

    start_upload = lambda do |file_size|
      msg = { cmd: 'startFileUpload', to: to_hpk.to_b64, file_size: file_size,
              metadata: { ctext: 'x', nonce: rand_bytes(24).to_b64 } }
      n = _make_nonce
      _post '/command', hpk, n, _client_encrypt_data(n, msg)
    end

    # Over the configured cap: rejected, and the reason is deliberately
    # named to the sender (it knows the size it declared) so clients can
    # tell this from any other 400
    start_upload.call(1001)
    _fail_response :bad_request
    assert_equal 'File size over relay limit', response.headers['X-Error-Details']

    # Exactly at the cap: accepted
    start_upload.call(1000)
    _success_response

    # nil disables the check (declared size bounded only by the sender quota)
    Rails.configuration.x.relay.file_store[:max_file_size] = nil
    start_upload.call(160 * 1024 * 1024) # over the old hardcoded 150Mb
    _success_response
  ensure
    Rails.configuration.x.relay.file_store[:max_file_size] = save
  end

end

