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

    # Only the sender hpk_from may write chunks. authoritative stored hpk_from, file_info stores hpk_from base64.
    unless @hpk.to_b64 == fl_info[:hpk_from]
      fail ReportError.new @controller,
        msg: "uploadFileChunk: caller #{dumpHex @hpk} is not the file sender"
    end

    # Bound the attacker-controlled part index before it is used as an Array index
    check_part_bound(fl_info, part_idx)

    # Fast pre-check against the first read: rejects an obvious over-cap. 
    # final race-safe check runs inside the transaction below
    check_size_bound(fl_info, part_idx, chunk_size)

    # If we already have that part in file_info
    logger.warn "#{WARN} Strange: client sending part #{part_idx} for uploadID #{dumpHex uploadID} while we already got it. Overwriting previous part." if find_part(fl_info, part_idx)
    mbx = Mailbox.new fl_info[:hpk_to]

    # Commit the chunk to disk BEFORE recording it in file_info: if the disk
    # write fails (e.g. ENOSPC) nothing is recorded and the client sees the
    # error; A chunk orphaned by a metadata failure here is swept later as an untracked file.
    unless FileManager.test_mode?
      @fm.save_data uploadID, data[:ctext].from_b64, part_idx
    end

     # === File info update ===
    lock_name = @mailbox.file_lock_tag(storage_id)
    # Watch the tracking key alongside the lock: the guarded re-read below
    # depends on it, and expiry, deleteFile or the stalled sweep can remove
    # it between that read and EXEC. Watched, such a removal aborts the EXEC
    # and the retry's fresh read observes NOT_FOUND instead of committing
    # metadata (and answering OK) for a file already reaped.
    tracking_key = mbx.storage_tag(@fm.storage_name_from_id(storage_id))
    deleted_mid_upload = false
    runRedisTransaction([lock_name, tracking_key], nil, "save file_info ##{part_idx}", Proc.new {
      # Guarded re-read. Re-check the size cap here against the FRESH state: on a WATCH conflict this proc re-runs, so concurrent chunks that each passed the
      # stale pre-check cannot push bytes_stored past the declared file_size. Skip for a file deleted mid-upload — the write block handles NOT_FOUND. Raising here aborts the store cleanly.
      fi = @mailbox.file_status_from_uid uploadID, @fm
      check_size_bound(fi, part_idx, chunk_size) unless fi[:status].to_s == 'NOT_FOUND'
      fi
    }) do | file_info, rds_transaction | # DATA WRITE BLOCK
      # A concurrent deleteFile removed this file after our first read; the guarded re-read now shows NOT_FOUND. 
      # Do NOT resurrect it - write nothing and let the already-on-disk chunk be swept as an orphan.
      if file_info[:status].to_s == 'NOT_FOUND'
        deleted_mid_upload = true
        next
      end
      deleted_mid_upload = false
      # set 2 sec lock to any random value
      rds_transaction.set lock_name, rand_str(24), **{ ex: 2 }
      # Record new part. parts is a lookup list keyed by :index (not a raw
      # Array indexed by part number), so a large index cannot pad the Array.
      new_part = {
        index: part_idx,
        chunk_size: chunk_size,
        nonce: data[:nonce]
      }
      # Overwriting a part changes only the size delta (one copy on disk
      # regardless of re-sends); a new part adds its whole size.
      file_info[:bytes_stored] += chunk_size_delta(file_info, part_idx, chunk_size)
      existing = file_info[:parts].find_index { |p| p && p[:index] == part_idx }
      if existing
        file_info[:parts][existing] = new_part
      else
        file_info[:parts] << new_part
      end
      # If last part already stored, dont override that status
      file_info[:status] = :UPLOADING unless file_info[:status] == "COMPLETE"
      file_info[:total_chunks] = file_info[:parts].length

      logger.info "Upload chunk: #{GREEN}#{dumpHex uploadID}#{ENDCLR} part #{BLUE}#{part_idx}; #{chunk_size}#{ENDCLR} bytes"

      # Last chunk processing
      if data[:last_chunk]
        file_info[:status] = :COMPLETE
        # exempt the finished file from the stalled-upload sweep
        mbx.mark_file_complete @fm.storage_name_from_id(storage_id), rds_transaction
        logger.info "Upload chunk: #{GREEN}complete#{ENDCLR}, #{BLUE}#{file_info[:total_chunks]}#{ENDCLR} parts"
      end
      mbx.save_file_info file_info, @hpk, storage_id, rds_transaction
      rds_transaction.del lock_name
    end
    # === end file_info update ===

    # File was deleted concurrently — report NOT_FOUND rather than a false OK
    return { status: :NOT_FOUND } if deleted_mid_upload

    return { status: :OK }
  end
end
