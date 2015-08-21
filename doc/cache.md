
This data is stored in the
[Rails Cache]
(http://guides.rubyonrails.org/caching_with_rails.html)

##### Relay Token

This is the token sent from the relay to a client.

Represented in the code this way:
```
@relay_token = RbNaCl::Random.random_bytes(32)
h2_client_token = h2(@client_token)
Rails.cache.write(h2_client_token, @relay_token, expires_in: @tmout)
```

##### Client Token
