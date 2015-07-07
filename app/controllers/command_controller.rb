class CommandController < ApplicationController

public
def process_cmd
  @hpk = _get_hpk
  _load_keys
  @body = request.body.read MAX_COMMAND_BODY # 100kb
  lines = _check_body @body
  nonce = _check_nonce b64dec lines[0]
  ctext = b64dec lines[1]
  data = _decrypt_data nonce, ctext
  mailbox = Mailbox.new @hpk

  rsp_nonce = _make_nonce

  # === Process command ===
  case data[:cmd]
  when 'count'
    data = { }
    data[_rand_str(2,8)] = _rand_str(8,8)
    data[:count] = mailbox.top
    data[_rand_str(2,8)] = _rand_str(8,8)
    render text:"#{b64enc rsp_nonce}\n#{_encrypt_data rsp_nonce,data}", status: :ok

  when 'upload'
    mbx = Mailbox.new data[:to]
    mbx.store @hpk,data[:payload]
    render nothing: true, status: :ok

  when 'download'
    count = mailbox.top > MAX_ITEMS ? MAX_ITEMS : mailbox.top
    start = data[:start] || 0
    raise "Bad download start position" unless start>=0 or start<mailbox.top
    payload = mailbox.read_all start,count

    client_nonce = _make_nonce
    box = RbNaCl::Box.new(@client_key, @session_key)
    traffic = box.encrypt(client_nonce, payload.to_json)
    render text:"#{b64enc client_nonce}\n"\
      "#{b64enc traffic}"

  when 'delete'
    for id in data[:ids]
      mailbox.delete_by_id id
    end
    # TODO: respond with encrypted count (same as cmd='count')
    render nothing: true, status: :ok
  end

  # === Error handling ===
  rescue RbNaCl::CryptoError => e
    _report_NaCl_error e
  rescue ZAXError => e
    e.http_fail
  rescue => e
    _report_error e
end

# === Helper Functions ===
private

def _load_keys
  @session_key = Rails.cache.read("session_key_#{@hpk}")
  @client_key = Rails.cache.read("client_key_#{@hpk}")
  raise HPK_keys.new(self,@hpk), "No cached session key" unless @session_key
  raise HPK_keys.new(self,@hpk), "No cached client key"  unless @client_key
end

def _check_body(body)
  lines = super body
  unless lines and lines.count==2 and lines[0].length==NONCE_B64
    raise "process command malformated body, #{ lines ? lines.count : 0} lines"
  end
  return lines
end

def _decrypt_data(nonce,ctext)
  box = RbNaCl::Box.new(@client_key,@session_key)
  d = JSON.parse box.decrypt(nonce,ctext)
  _check_command d.reduce({}) { |h,(k,v)| h[k.to_sym]=v; h }
end

def _encrypt_data(nonce,data)
  box = RbNaCl::Box.new(@client_key,@session_key)
  b64enc box.encrypt(nonce,data.to_json)
end

def _rand_str(min,size)
  (b64enc rand_bytes min+rand(size)).gsub '=',''
end

def _check_command(data)
  all = %w[count upload download delete]

  raise 'process: missing command' unless data[:cmd]
  raise "process: unknown command #{data[:cmd]}" unless all.include? data[:cmd]

  if data[:cmd] == 'upload'
    raise "process: no destination HPK in upload" unless data[:to]
    _check_hpk data[:to]
    raise "process: no payload in upload" unless data[:payload]
  end

  if data[:cmd] == 'delete'
    raise "process: no ids to delete" unless data[:ids]
  end

  return data
end

def _report_error(e)
  logger.warn "#{WARN} Process command aborted:\n#{@body}\n#{EXPT} #{e}"
  head :precondition_failed, x_error_details:
    "Can't process command: #{e.message}"
end
end