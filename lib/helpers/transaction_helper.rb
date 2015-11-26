require 'utils'
require 'errors/transaction'

module TransactionHelper
  include Utils
  include Errors

  # Watch the hash index of a given mailbox - this way redis will do only one
  # operation at a time on that specific mailbox. We will keep retrying the
  # transaction a few times per config value and send an exception up if it
  # still fails after that
  def runMbxTransaction(hpk, op = '')
    limit = Rails.configuration.x.relay.mailbox_retry
    count, complete, res = 0, false, nil
    while count < limit and not complete
      rds.watch("mbx_#{hpk}") do
        rds.multi
        yield
        res = rds.exec
        complete = ! res.nil?
        unless complete
          count += 1
          sleep 0.1 + rand() * 0.1 # let other mbx writes complete
          logger.warn "#{INFO_NEG} mailbox #{dumpHex hpk}, retry #{op}/#{count}"
        end
      end
    end
    if count >= limit and not complete
      raise TransactionError.new(self,hpk),
        "#{op} in mailbox #{dumpHex hpk} transaction failure"
    end
    return complete ? res : nil
  end
end
