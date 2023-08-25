# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class ZaxCommand
  include Utils
  include Helpers::NonceHelper

  def initialize(hpk,mailbox)
    @hpk = hpk
    @mailbox = mailbox
  end

  # All commands should implement process(data)
  # All implemetnations should call super(data) first
  def process(data)
  end
end
