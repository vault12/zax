# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

# Default to production
rails_env = ENV['RAILS_ENV'] || 'production'

if rails_env == 'production'
  # Change to match your CPU core count
  workers Integer(ENV["ZAX_WORKERS"] || 12)

  # Min and Max threads per worker
  threads 1, Integer(ENV["ZAX_THREADS"] || 6)
end

if rails_env == 'development'
  workers 2
  threads 1, 2
end

app_dir = File.expand_path("../..", __FILE__)
shared_dir = "#{app_dir}/shared"

environment rails_env

# Set up socket location
bind "unix://#{shared_dir}/sockets/puma.sock"

# Logging
stdout_redirect "#{shared_dir}/log/puma.stdout.log", "#{shared_dir}/log/puma.stderr.log", true

# Set master PID and state locations
pidfile "#{shared_dir}/pids/puma.pid"
state_path "#{shared_dir}/pids/puma.state"
activate_control_app

on_worker_boot do
  # require "active_record"
  # ActiveRecord::Base.connection.disconnect! rescue ActiveRecord::ConnectionNotEstablished
  # ActiveRecord::Base.establish_connection(YAML.load_file("#{app_dir}/config/database.yml")[rails_env])
end

preload_app!
