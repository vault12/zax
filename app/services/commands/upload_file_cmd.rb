# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class Commands::UploadFileCmd < Commands::FileCmd
  include Helpers::TransactionHelper

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
    }) do | file_info, rds_transaction | # DATA WRITE BLOCK
      # set 2 sec lock to any random value
      rds_transaction.set lock_name, rand_str(24), **{ ex: 2 }
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
      mbx.save_file_info file_info, @hpk, storage_id, rds_transaction
      rds_transaction.del lock_name
    end
    # === end file_info update ===

    unless FileManager.test_mode?
      @fm.save_data uploadID, data[:ctext].from_b64, part_idx
    end

    return { status: :OK }
  end
end
