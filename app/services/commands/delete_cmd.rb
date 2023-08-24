# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class Commands::DeleteCmd < ZaxCommand
  def process(data)
    super data
    return nil unless data[:payload]
    logger.info "#{INFO_GOOD} #{RED}deleting#{ENDCLR} from mbx #{MAGENTA}'#{dumpHex @hpk}'#{ENDCLR}"
    @mailbox.delete_list data[:payload]
    @mailbox.count
  end
end
