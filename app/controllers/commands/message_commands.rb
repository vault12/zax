# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'commands/zax_command'

class UploadCmd < ZAXCommand
  def process(data)
    super data

    hpkto = data[:to].from_b64
    mbx = Mailbox.new data[:to]

    # Nonce is included for A->B private messages
    # Make one if payload is a plain text message
    msg_nonce = if (data[:payload].class==Hash and data[:payload][:nonce])
      then data[:payload][:nonce].from_b64
      else _make_nonce end

    # Ctext of private messages or plain text payload
    msg = if (data[:payload].class==Hash and data[:payload][:ctext])
      then data[:payload][:ctext]
      else data[:payload] end

    logger.info "#{INFO_GOOD} stored item #{GREEN}#{dumpHex msg_nonce}#{ENDCLR} mbx #{MAGENTA}'#{dumpHex @hpk}' => '#{dumpHex hpkto}'#{ENDCLR}"
    mbx.store @hpk, msg_nonce, msg
  end
end

class DownloadCmd < ZAXCommand
  def process(data)
    super data
    count = data[:count] || @mailbox.count > MAX_ITEMS ? MAX_ITEMS : @mailbox.count
    start = data[:start] || 0
    fail ReportError.new self, msg: 'Bad download start position' unless start >= 0 || start < @mailbox.count
    logger.info "#{INFO_GOOD} downloading #{BLUE}#{count}#{ENDCLR} messages in mbx #{MAGENTA}'#{dumpHex @hpk}'#{ENDCLR}"
    wire_format @mailbox.read_all start, count
  end

  def wire_format(messages)
    payload_array = []
    messages.each do |message|
      payload = {}
      payload[:data] = message[:data]
      payload[:time] = message[:time]
      payload[:from] = message[:from].to_b64
      payload[:nonce] = message[:nonce].to_b64
      payload[:kind] = message[:kind]
      payload_array.push payload
    end
    payload_array
  end
end

class CountCmd < ZAXCommand
  def process(data)
    super data
    cnt = @mailbox.count
    logger.info "#{INFO} #{BLUE}#{cnt}#{ENDCLR} items in mbx #{MAGENTA}#{dumpHex @hpk}#{ENDCLR}"
    return cnt
  end
end


class StatusCmd < ZAXCommand
  def process(data)
    super data
    storage_token = data[:token].from_b64
    @mailbox.check_msg_status storage_token
  end
end

class DeleteCmd < ZAXCommand
  def process(data)
    super data
    return nil unless data[:payload]
    logger.info "#{INFO_GOOD} #{RED}deleting#{ENDCLR} from mbx #{MAGENTA}'#{dumpHex @hpk}'#{ENDCLR}"
    @mailbox.delete_list data[:payload]
    @mailbox.count
  end
end
