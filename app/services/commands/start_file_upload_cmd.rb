# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class Commands::StartFileUploadCmd < Commands::FileCmd
  include Helpers::HpkHelper

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
