# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class Commands::FileStatusCmd < Commands::FileCmd
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
