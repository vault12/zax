# Copyright (c) 2017-2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class Commands::FileCmd < ZaxCommand

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

  # Reject an out-of-range part index. The bound is derived from the file's
  # declared size: an upload may use at most ceil(file_size /
  # MIN_BYTES_PER_PART) part slots. Every part is a separate file on disk,
  # so this ties the file count on disk to the bytes the declaration holds
  # against the sender's quota — at worst one file per kb declared. Any
  # client chunking at MIN_BYTES_PER_PART or larger fits whatever the file
  # size; valid indices are 0..allowed-1.

  def check_part_bound(file_info, part_idx)
    allowed = (file_info[:file_size].to_i + MIN_BYTES_PER_PART - 1) / MIN_BYTES_PER_PART
    fail ReportError.new @controller,
      msg: "file part #{part_idx} out of range (declared size #{file_info[:file_size]} allows #{allowed} parts, indices 0..#{allowed - 1})" if part_idx >= allowed
  end

  # Find a stored part record by its index (parts is a list, not positionally
  # indexed by part number, so that an attacker-chosen index cannot pad the Array).
  def find_part(file_info, part_idx)
    file_info[:parts].find { |p| p && p[:index] == part_idx }
  end

  # Bytes this chunk would add to the stored total: the whole chunk for a new
  # part, or just the size delta when overwriting an already-stored part 
  def chunk_size_delta(file_info, part_idx, chunk_size)
    existing = find_part(file_info, part_idx)
    existing ? chunk_size - existing[:chunk_size].to_i : chunk_size
  end

  # Enforce the declared file_size: reject a chunk that would push the stored
  # total past what the client declared at startFileUpload. We allow
  # `per_chunk_overhead` bytes per stored part on top of file_size
  def check_size_bound(file_info, part_idx, chunk_size)
    file_size = file_info[:file_size].to_i
    existing = find_part(file_info, part_idx)
    delta = existing ? chunk_size - existing[:chunk_size].to_i : chunk_size
    projected_bytes = file_info[:bytes_stored].to_i + delta
    projected_parts = file_info[:parts].length + (existing ? 0 : 1)
    limit = file_size + projected_parts * @fm.per_chunk_overhead
    fail ReportError.new @controller,
      msg: "uploadFileChunk: upload exceeds declared file_size #{file_size} + overhead (#{projected_bytes} > #{limit} bytes)" if projected_bytes > limit
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
