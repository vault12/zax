source 'https://rubygems.org'

gem 'rails', '~> 7.2', '>= 7.2.3.1'

gem 'puma', '~> 7.2'
# gem "sprockets-rails"

group :development, :test do
  gem 'spring'
  gem 'minitest-reporters'
  gem 'pry', '~> 0.14.2'
end

gem 'kgio'

gem 'redis'
gem 'redis-rails'

# activesupport 7.2's :redis_cache_store is incompatible with connection_pool 3.x
# (ConnectionPool.new signature change -> ArgumentError on boot). Hold at 2.x.
gem 'connection_pool', '< 3'

gem 'rbnacl'

gem 'base32'

gem 'mutex_m', '~> 0.3.0'

# To use bundle install
# gem install bundler

# To use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# To use Jbuilder templates for JSON
# gem 'jbuilder'

# Deploy with Capistrano
# gem 'capistrano', :group => :development

# To use debugger
# gem 'ruby-debug19', :require => 'ruby-debug'
