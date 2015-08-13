

Zax requires Redis to run.

Install Redis from here: http://redis.io/download

Then bring up an instance of Redis

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
