# Copyright (c) 2017 Vault12, Inc.
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
