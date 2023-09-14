# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

include Errors

class FileIOTest < ActionController::TestCase
public

test 'file config limits' do
  save = Rails.configuration.x.relay.file_store[:max_chunk_size]
  Rails.configuration.x.relay.file_store[:max_chunk_size] = MAX_COMMAND_BODY-1000 # slightly less then 1k

  assert_raises ConfigError do
    fm = FileManager.new
  end

  Rails.configuration.x.relay.file_store[:max_chunk_size] = save
end

test 'file storage path' do
  fm = FileManager.new
  assert_not_nil fm
  assert_not_nil fm.storage_path
  assert_equal Rails.configuration.x.relay.file_store[:root], fm.storage_path

  # empty config
  save_it = Rails.configuration.x.relay.file_store[:root]
  Rails.configuration.x.relay.file_store[:root] = "" # now empty

  fm = FileManager.new
  assert_not_nil fm
  assert_not_nil fm.storage_path
  assert_equal "#{Rails.root}/shared/uploads/", fm.storage_path

  missing_slash = "#{Rails.root}/shared/uploads"
  Rails.configuration.x.relay.file_store[:root]=missing_slash
  fm = FileManager.new
  assert_not_nil fm
  assert_not_nil fm.storage_path
  # trailing `/` enforced
  assert_not_equal missing_slash, fm.storage_path
  assert_equal (missing_slash+'/'), fm.storage_path

  Rails.configuration.x.relay.file_store[:root]=save_it # restore it
end

test 'create storage dir' do
  # assert_raises(Errors::ZaxError) { fm = FileManager.new }

  fm = FileManager.new
  # always a storage dir after constructor
  assert File.directory?(fm.storage_path)

  # move uploads => uploads2
  u2 = fm.storage_path.sub(/\/$/,'2/')
  FileUtils.rmtree(u2) if File.directory?(u2)
  File.rename fm.storage_path,u2

  # now there is no storage dir
  assert_not File.directory?(fm.storage_path)
  fm = FileManager.new
  # storage dir recreated
  assert File.directory?(fm.storage_path)

  # restore old storage dir in case it had any files
  FileUtils.rmtree fm.storage_path
  File.rename u2,fm.storage_path
end

test 'secret seed' do
  # seed exists in config
  test = "jEPjU+8lB5XdSOhffS2GHtMXpRpEM12k/HML0SUYMEo"
  Rails.configuration.x.relay.file_store[:secret_seed] = test
  fm = FileManager.new
  assert_equal fm.seed, test

  # seed exists in file
  Rails.configuration.x.relay.file_store[:secret_seed] = ""
  fm = FileManager.new
  seed_path = fm.storage_path+"secret_seed.txt"
  file_seed = File.open(seed_path, 'r') { |f| f.read() }
  assert_equal file_seed,fm.seed

  seed_path2 = fm.storage_path+"secret_seed2.txt"
  # seed created if there is no config, no file
  Rails.configuration.x.relay.file_store[:secret_seed] = ""

  FileUtils.mv seed_path,seed_path2 if File.exist?(seed_path)
  assert_not File.exist?(seed_path)

  fm = FileManager.new
  assert_not_nil fm.seed
  assert fm.seed.length>32

  if File.exist?(seed_path2)
    FileUtils.rm seed_path
    FileUtils.mv seed_path2,seed_path
  end

  Rails.configuration.x.relay.file_store[:secret_seed] = nil
end

test 'storage name' do
  hpk_from = h2(RbNaCl::PrivateKey.generate.public_key)
  hpk_to = h2(RbNaCl::PrivateKey.generate.public_key)
  fm = FileManager.new

  nonce = rand_bytes NONCE_LEN
  uID = h2(hpk_from+hpk_to+nonce+fm.seed)
  token = fm.create_storage_token(hpk_from,hpk_to,nonce,0)
  assert_equal token[:uploadID], uID

  Rails.configuration.x.relay.file_store[:secret_seed] = "bgi5UzAYLEjfHvWxFEbxUE3tVOElydt63Pv3Hs99avw"
  fm = FileManager.new

  # this works with bad hpks because name is derived from hash
  assert_equal "orn4mxjceonlkemkctmtzcbizs72ab63sjeizjdpqoy2cvetaxyq", fm.create_storage_token("hpk1","hpk2","123",0)[:storage_name]

end

end
