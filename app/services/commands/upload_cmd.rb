# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

class Commands::UploadCmd < ZaxCommand
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
