zax
=====

[![Build Status](https://magnum.travis-ci.com/vault12/zax.svg?token=g8FwU726sRsZ5HdMFemF&branch=master)](https://magnum.travis-ci.com/vault12/zax)

Zax requires Redis to run.

##### Install Redis

Download Redis from here: http://redis.io/download

Building Redis: https://github.com/antirez/redis#building-redis

Running Redis: https://github.com/antirez/redis#running-redis

##### Install Zax

```
git clone git@github.com:vault12/zax.git
gem install bundler
bundle install
```

To bring up rails run this command:

```
rails s -p 8080
```

To test the code run this command:

```
rake test
rake test:integration
rake test:controllers
rake test -v test/integration/mailbox_test.rb
```

Zax works with this version of Ruby:

```
ruby 2.2.2p95 (2015-04-13 revision 50295)
```
