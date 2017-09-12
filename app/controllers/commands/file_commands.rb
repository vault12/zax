# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'commands/zax_command'

class FileCmd < ZAXCommand

  def initialize(hpk,mailbox,ctrl)
    super hpk, mailbox
    @controller = ctrl
    @fm = FileManager.new(ctrl)
  end

  def unpack_file_request_data (data)
    uploadID = data[:uploadID].from_b64 if data[:uploadID]
    storage_id = @fm.storage_from_upload(uploadID) if uploadID
    part_idx = data[:part]
    ctext = data[:ctext].from_b64 if data[:ctext]
    chunk_size = ctext.length if data[:ctext]
    [uploadID,storage_id,part_idx,ctext,chunk_size]
  end

  def log_file_info(file_info)
    return unless Rails.logger.level <= 1 # :info or :debug
    f =[:hpk_from,:hpk_to]
    for h in f
      file_info["log_#{h}"] = dumpHex(file_info[h].from_b64) if file_info[h]
      file_info.delete h
    end
    logger.info file_info
    for h in f; file_info.delete "log_#{h}"; end
  end
end

class StartFileUploadCmd < FileCmd
  include HPKHelper

  def process(data)
    super data
    # File recepient hpk
    hpkto = _get_hpk data[:to]

    # Size of the original file
    file_size = data[:file_size]

    # Nonce payload encrypted with
    payload_nonce = data[:metadata][:nonce].from_b64

    upload_token = @fm.create_storage_token(@hpk, hpkto, payload_nonce, file_size)

    file_summary = {
      # For hpk_to: encrypted info about the file
      # Only hpk_to has key to decrypt this ctext
      ctext: data[:metadata][:ctext],
      nonce: data[:metadata][:nonce],

      # Give uploadID to hpk_to for download command
      uploadID: upload_token[:uploadID].to_b64,
    }

    logger.info "Start upload: #{MAGENTA}#{dumpHex @hpk}=>#{dumpHex hpkto} #{GREEN}#{dumpHex upload_token[:uploadID]}#{ENDCLR} file, original file #{BLUE}#{data[:file_size]}#{ENDCLR} bytes"

    # This is a message hpk_to will receive as regular message
    # with kind==:file
    mbx = Mailbox.new data[:to]
    res = mbx.store @hpk, payload_nonce, file_summary.to_json,
      :file, upload_token

    # This is the payload hpk_from will receive as response,
    # including newly generated uploadID for upload commands
    return {
     # uploadID for hpk_from, passed to uploadFileChunk
     uploadID: upload_token[:uploadID].to_b64,

     # Max chunk size this relay will allow
     max_chunk_size: @fm.max_chunk_size,

     # Token about message (with file info) we are sending.
     # Glow Mailbox.relay_msg_status to check status of that msg after
     storage_token: res[:storage_token].to_b64,
    }
  end
end

class UploadFileCmd < FileCmd
  include TransactionHelper

  def process(data)
    uploadID, storage_id, part_idx, ctext, chunk_size = unpack_file_request_data(data)
    fail ReportError.new @controller, msg: "uploadFileChunk: chunk_size #{chunk_size} while max_size is #{@fm.max_chunk_size}" if chunk_size>@fm.max_chunk_size

    # Read first time to see if file exists
    fl_info = @mailbox.file_status_from_uid uploadID, @fm
    return nil if fl_info[:status] == :NOT_FOUND

    # If we already have that part in file_info
    logger.warn "#{WARN} Strange: client sending part #{part_idx} for uploadID #{dumpHex uploadID} while we alrady got it. Overwriting previous part." if fl_info[:parts][part_idx]
    mbx = Mailbox.new fl_info[:hpk_to]

     # === File info update ===
    lock_name = @mailbox.file_lock_tag(storage_id)
    runRedisTransaction(lock_name, nil, "save file_info ##{part_idx}", Proc.new {
      # Data read guarded inside transaction for processing
       @mailbox.file_status_from_uid uploadID, @fm
    }) do | file_info | # DATA WRITE BLOCK
      # set 2 sec lock to any random value
      rds.set lock_name, rand_str(24), { ex: 2 }
      # Record new part
      new_part = {
        index: part_idx,
        chunk_size: chunk_size,
        nonce: data[:nonce]
      }
      file_info[:parts][part_idx] = new_part
      file_info[:bytes_stored] += chunk_size
      # If last part already stored, dont override that status
      file_info[:status] = :UPLOADING unless file_info[:status] == "COMPLETE"
      file_info[:total_chunks] = file_info[:parts].length

      logger.info "Upload chunk: #{GREEN}#{dumpHex uploadID}#{ENDCLR} part #{BLUE}#{part_idx}; #{chunk_size}#{ENDCLR} bytes"

      # Last chunk processing
      if data[:last_chunk]
        file_info[:status] = :COMPLETE
        logger.info "Upload chunk: #{GREEN}complete#{ENDCLR}, #{BLUE}#{file_info[:total_chunks]}#{ENDCLR} parts"
      end
      mbx.save_file_info file_info, @hpk, storage_id
      rds.del lock_name
    end
    # === end file_info update ===

    unless FileManager.test_mode?
      @fm.save_data uploadID, data[:ctext].from_b64, part_idx
    end

    return { status: :OK }
  end
end

class DownloadFileCmd < FileCmd
  def process(data)
    super data
    uploadID, storage_id, part_idx = unpack_file_request_data(data)
    file_info = @mailbox.file_status_from_uid uploadID,@fm
    return nil if file_info[:status] == :NOT_FOUND

    logger.info "Download chunk: #{GREEN}#{dumpHex uploadID}#{ENDCLR} part #{BLUE}#{part_idx}#{ENDCLR} bytes"

    part = file_info[:parts][part_idx]
    fail ReportError.new @controller, msg: "missing part #{part_idx} from file #{dumpHex uploadID} with #{file_info[:total_chunks]} parts" unless part

    payload = {
      nonce: part[:nonce]
    }
    file = nil
    unless FileManager.test_mode?
      file = @fm.load_data(uploadID, part_idx).to_b64
    else
      # Random test fill
      file = rand_bytes(part[:chunk_size]).to_b64
    end

    return [payload,file]
  end
end

class FileStatusCmd < FileCmd
  def process(data)
    super data
    uID = data[:uploadID].from_b64
    logger.info "File status: #{GREEN}#{dumpHex uID}#{ENDCLR}"
    file_info = @mailbox.file_status_from_uid uID, @fm
    file_info.delete :parts  # used only internally
    log_file_info file_info
    return file_info
  end
end

class DeleteFileCmd < FileCmd
  def process(data)
    uploadID, storage_id = unpack_file_request_data(data)
    file_info = @mailbox.file_status_from_uid uploadID, @fm
    return { status: :NOT_FOUND } if file_info[:status] == :NOT_FOUND

    # Delete binary chunks
    @fm.delete_file uploadID, file_info[:total_chunks].to_i
    @mailbox.delete_file_info file_info[:hpk_from].from_b64, storage_id
    return { status: :OK }
  end
end
