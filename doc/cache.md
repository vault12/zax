
This data is stored in the
[Rails Cache]
(http://guides.rubyonrails.org/caching_with_rails.html)


## Data held for command requests

These keys are held during the
[Relay Command]
(https://github.com/vault12/docs/blob/master/crypto.v12.md#alice-sends--relay-commands)
phase of communication.

```
Rails.cache.write("session_key_#{hpk}",@session_key)
Rails.cache.write("client_key_#{hpk}",@client_key.public_key)
```

##### Hpk

## Data held for session and prove requests

##### Client Token

The client token is sent from the client to the relay during the

*POST /start_session/*

Represented in the code this way:
```
h2_client_token = h2(@client_token)
Rails.cache.write("client_token_#{h2_client_token}", @client_token, expires_in: @tmout)
```

##### Client Token maps to Relay Token

The relay token is sent from the relay to a client during the

*POST /start_session/*

Represented in the code this way:
```
@relay_token = RbNaCl::Random.random_bytes(32)
h2_client_token = h2(@client_token)
Rails.cache.write("relay_token_#{h2_client_token}", @relay_token, expires_in: @tmout)
```

##### Client Token maps to Session Key

The relay generates a Session Key Pair during the

*POST /verify_session/*

Represented in the code in this way:
```
@session_key = RbNaCl::PrivateKey.generate
Rails.cache.write("session_key_#{h2_client_token}", @session_key, :expires_in => @tmout)
```
