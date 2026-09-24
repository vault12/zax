# Copyright (c) 2026 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
require 'test_helper'

# secret_seed establishment must never overwrite an existing seed and
# concurrent establishment must converge on one value.
class FileSeedTest < ActiveSupport::TestCase

  setup do
    @dir = "#{Rails.root}/tmp/seed_test_#{rand_str 8}/"
    FileUtils.mkdir_p @dir
    @save_root = Rails.configuration.x.relay.file_store[:root]
    @save_seed = Rails.configuration.x.relay.file_store[:secret_seed]
    Rails.configuration.x.relay.file_store[:root] = @dir
    Rails.configuration.x.relay.file_store[:secret_seed] = ''
    ENV.delete('ZAX_SECRET_SEED')
  end

  teardown do
    Rails.configuration.x.relay.file_store[:root] = @save_root
    Rails.configuration.x.relay.file_store[:secret_seed] = @save_seed
    ENV.delete('ZAX_SECRET_SEED')
    FileUtils.rm_rf @dir
  end

  def seed_path = "#{@dir}secret_seed.txt"

  test 'first boot generates and persists a seed' do
    assert_not File.exist?(seed_path)
    fm = FileManager.new
    assert File.exist?(seed_path)
    assert_operator fm.seed.length, :>=, 32
    assert_equal File.read(seed_path), fm.seed
    # the seed derives every storage name — never world-readable, whatever
    # umask the launching process carried
    assert_equal 0o600, File.stat(seed_path).mode & 0o777, 'seed file must be 0600'
  end

  test 'existing seed file is never overwritten and is loaded verbatim' do
    existing = 'a-hand-written-seed-value-over-32-chars-long!!'
    File.write(seed_path, existing)
    fm = FileManager.new
    assert_equal existing, fm.seed, 'loaded the existing seed unchanged'
    assert_equal existing, File.read(seed_path), 'file left byte-identical'
  end

  test 'a second FileManager converges on the already-established seed' do
    first = FileManager.new.seed
    # Clear the in-config seed so the second instance must re-load from file
    Rails.configuration.x.relay.file_store[:secret_seed] = ''
    second = FileManager.new.seed
    assert_equal first, second, 'both converge on the persisted seed'
  end

  test 'ENV seed is used when no file exists' do
    ENV['ZAX_SECRET_SEED'] = env_seed = 'env-injected-seed-over-32-characters-longxx'
    assert_equal env_seed, FileManager.new.seed
    # ENV-only deploy: nothing persisted to disk
    assert_not File.exist?(seed_path)
  end

  test 'config seed is used when set (matching other sources)' do
    seed = 'agreed-seed-value-over-32-characters-longyy'
    File.write(seed_path, seed)
    ENV['ZAX_SECRET_SEED'] = seed
    Rails.configuration.x.relay.file_store[:secret_seed] = seed
    assert_equal seed, FileManager.new.seed
  end

  # config/ENV and the persisted file disagreeing is a fatal
  # ambiguity — we can't know which is the authoritative long-term seed.
  test 'config seed disagreeing with the file is fatal' do
    File.write(seed_path, 'file-seed-value-that-is-over-32-characters-xx')
    Rails.configuration.x.relay.file_store[:secret_seed] = 'config-seed-over-32-characters-long-value-x'
    assert_raises(Errors::ConfigError) { FileManager.new }
    # file left untouched
    assert_equal 'file-seed-value-that-is-over-32-characters-xx', File.read(seed_path)
  end

  test 'ENV seed disagreeing with the file is fatal' do
    File.write(seed_path, 'file-seed-value-that-is-over-32-characters-xx')
    ENV['ZAX_SECRET_SEED'] = 'env-injected-seed-over-32-characters-longxx'
    assert_raises(Errors::ConfigError) { FileManager.new }
  end

  # A too-short EXISTING seed file must abort startup, not regenerate: the
  # stored files are bound to it and it must not be overwritten.
  test 'a too-short existing seed file is fatal and left untouched' do
    File.write(seed_path, weak = 'only16byteseed!!') # 16 chars, < 32
    assert_raises(Errors::ConfigError) { FileManager.new }
    assert_equal weak, File.read(seed_path), 'weak seed file must not be overwritten'
  end

  test 'a too-short config seed is fatal' do
    Rails.configuration.x.relay.file_store[:secret_seed] = 'shortconfig'
    assert_raises(Errors::ConfigError) { FileManager.new }
  end

  test 'a too-short ENV seed is fatal' do
    ENV['ZAX_SECRET_SEED'] = 'shortenv'
    assert_raises(Errors::ConfigError) { FileManager.new }
  end
end
