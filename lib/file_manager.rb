# Copyright (c) 2017 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'base32'

class FileManager
  include Utils
  include Errors
  include Helpers::TransactionHelper

  STATUS_CODES = %i(NOT_FOUND START UPLOADING COMPLETE)

  attr_reader :storage_path
  attr_reader :max_chunk_size
  attr_reader :seed

  def self.is_enabled?
    Rails.configuration.x.relay.file_store[:enabled]
  end

  def self.mode?
    Rails.configuration.x.relay.file_store[:mode]
  end

  def self.test_mode?
    self.mode? == :test
  end

  def initialize(ctrl =nil)
    @controller = ctrl # parent controller to report errors

    fsr = Rails.configuration.x.relay.file_store[:root]
    @storage_path = (not fsr.empty?) ? fsr : "#{Rails.root}/shared/uploads/"

    # ensure it always terminated by '/'
    @storage_path+='/' unless @storage_path.last == '/'

    _ensure_storage_dir()
    _ensure_secret_seed()

    @max_chunk_size = Rails.configuration.x.relay.file_store[:max_chunk_size]
    @max_chunk_size = 100*1024 if @max_chunk_size.nil? or @max_chunk_size<1

    # TODO: new class to trigger severe_error
    # Reserve 1k for command wrappers
    if @max_chunk_size >= MAX_COMMAND_BODY - 1024
      fail ConfigError.new @controller,
        msg: "`max_chunk_size` config param have to be 1kb smaller then MAX_COMMAND_BODY build constant"
    end
  end

  def create_storage_token(hpk_from,hpk_to,nonce,msz)
    uID = h2(hpk_from+hpk_to+nonce+@seed)
    storage_id = storage_from_upload(uID)
    { hpk_from: hpk_from,
      hpk_to: hpk_to,
      file_size: msz,
      uploadID: uID,
      storage_id: storage_id,
      storage_name: storage_name_from_id(storage_id),
    }
  end

  def storage_from_upload(uploadID)
    h2(uploadID+@seed)
  end

  def storage_name_from_id(storage_id, part = nil)
    name = Base32.encode(storage_id).gsub('=','').downcase
    part ? "#{name}.#{part}.bin" : name
  end

  def save_data(uploadID, data, part)
    file_name = storage_name_from_id storage_from_upload(uploadID), part
    File.open("#{storage_path}#{file_name}", 'wb') do |f|
      f.write data
      f.flush
    end
  end

  def load_data(uploadID, part)
    data = nil
    file_name = storage_name_from_id storage_from_upload(uploadID), part
    File.open("#{storage_path}#{file_name}", 'rb') do |f|
      data = f.read
    end
    return data
  end

  def delete_file(uploadID, total_parts)
    # Mark file as ok to delete by job if this delete fails
    rds.del "#{STORAGE_PREFIX}#{storage_name_from_id(storage_from_upload(uploadID))}"
    unless self.class.test_mode?
      for part in (0...total_parts)
        if delete_data uploadID, part
          logger.info "#{RED}Delete#{ENDCLR} chunk: #{GREEN}#{dumpHex uploadID}#{ENDCLR} part #{BLUE}#{part}#{ENDCLR}"
        end
      end
    end
  end

  def delete_data(uploadID, part)
    file_name = storage_name_from_id(storage_from_upload(uploadID), part)
    full = "#{storage_path}#{file_name}"
    File.exist?(full) ? File.delete(full) : nil
  end

  def delete_expired_all
    all = rds.smembers(ZAX_GLOBAL_FILES)
    whitelist = []
    for name in all
      storage_name = name.sub(STORAGE_PREFIX,'')
      # file still active
      if rds.get name
        whitelist.push storage_name
        logger.info  "Whitelist #{storage_name}"
        next
      end

      # delete known expired files
      rds.srem(ZAX_GLOBAL_FILES, name)
      for file in Dir["#{storage_path}#{storage_name}.*.bin"]
        File.delete file
        logger.info  "#{INFO} Delete expired #{file}"
      end
    end

    # prune storage_path
    for file in Dir["#{storage_path}*.*.bin"]
      storage_name = file.sub(/\.\d*\.bin/,'').match(/\w*$/)[0]
      next if storage_name and whitelist.include? storage_name
      File.delete file
      logger.info  "#{INFO} Prunning #{file}"
    end
  end

  private
  def _ensure_storage_dir
    FileUtils.mkdir_p(@storage_path) unless File.directory?(@storage_path)
  end

  def _seed_path
    @storage_path+"secret_seed.txt"
  end

  def _valid_seed?
    # Config file takes precedence over text file
    @seed = Rails.configuration.x.relay.file_store[:secret_seed]

    # If no config value, load from "secret_seed.txt"
    if (@seed.nil? or @seed.empty?) and File.exist?(_seed_path)
      @seed = File.open(_seed_path, 'r') { |file| file.read() }
    end

    # return false if all above failed, no saved seed
    return (not @seed.nil? and @seed.length >= 32)
  end

  def _ensure_secret_seed
    unless _valid_seed?
      @seed = rand_str 32
      Rails.configuration.x.relay.file_store[:secret_seed] = @seed
      File.open(_seed_path, 'w') do |file|
        file.write(@seed)
      end
    end
  end

end
