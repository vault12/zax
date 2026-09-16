# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class Commands::DownloadCmd < ZaxCommand
  def process(data)
    super data
    # Honor the client's requested page size, capped at MAX_ITEMS. 
    count = [data[:count] || @mailbox.count, MAX_ITEMS].min
    start = data[:start] || 0
    # Note: start/count are validated as non-negative Integers in check_command
    # Upper bound handled gracefully by read_all (returns empty array if out of bounds)
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
