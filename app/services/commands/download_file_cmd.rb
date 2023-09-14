# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class Commands::DownloadFileCmd < Commands::FileCmd
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
