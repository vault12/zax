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

end

