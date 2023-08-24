# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class Commands::StatusCmd < ZaxCommand
  def process(data)
    super data
    storage_token = data[:token].from_b64
    @mailbox.check_msg_status storage_token
  end
end
