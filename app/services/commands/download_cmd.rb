# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class Commands::DownloadCmd < ZaxCommand
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
