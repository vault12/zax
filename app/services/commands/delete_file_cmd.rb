# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class Commands::DeleteFileCmd < Commands::FileCmd
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
