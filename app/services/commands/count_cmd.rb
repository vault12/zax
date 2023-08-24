# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class Commands::CountCmd < ZaxCommand
  def process(data)
    super data
    cnt = @mailbox.count
    logger.info "#{INFO} #{BLUE}#{cnt}#{ENDCLR} items in mbx #{MAGENTA}#{dumpHex @hpk}#{ENDCLR}"
    return cnt
  end
end
