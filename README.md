# Zax [![Build Status](https://travis-ci.org/vault12/zax.svg?branch=master)](https://travis-ci.org/vault12/zax)

Zax is a [NaCl-based Cryptographic Relay](https://s3-us-west-1.amazonaws.com/vault12/zax_infogfx.jpg), easily accessed via the [Glow](https://github.com/vault12/glow) library. You can read the full [technical specification here](http://bit.ly/nacl_relay_spec).

Zax relay nodes are asyncronous "dead drops" for mobile communications. Relays are intended to be multiplied for reliability and form a distributed network. Individual devices send messages to a mutually determenistic subset of relays and check the same for response traffic.

**Zax v2.0 Update** summary is [here](#-version-20-updates)
![Zax Infographics](https://bit.ly/zax_relay)

## Features
- **Universal**: All Zax Relay nodes are mutually interchangeable and operate in a global address space. Any mobile device can contact any node to pass private messages to any other mobile device without a pre-existing setup or registration with that Relay.
- **Encrypted end-to-end**: It is cryptographically impossible for a Zax Relay node to decrypt the traffic passing though it between endpoint devices even if the Relay is taken over by an external agency.
- **Ephemeral**: Zax Relay nodes do not store anything in permanent storage, and operate only with *memory-based* ephemeral storage. The Relay acts as an encrypted memory cache shared between mobile devices. Key information is kept in memory only and erased within minutes after completing the session. Encrypted messages are kept in memory for future collection and are erased after a few days if not collected by the target device.
- **Well-known relays**: A deployed Zax Relay node's URL/identity should be well known and proven by a TLS certificate. Applications might implement certificate pinning for well-known relays of their choosing. A mobile app could keep a list of geographically dispersed relays and use a deterministic subset of them to send & receive asynchronous messages to/from another mobile device.
- **Identification privacy**: After establishing temporary keys for each session, a Zax Relay node never stores long-term identity keys of the endpoint devices. When the protocol requires the verification of public key ownership, these operations happen in memory only and are immediately erased afterward. In the future, we're planning on leveraging Zero Knowledge Proofs to eliminate disclosure of long term public keys (and therefore device identity) to a Zax Relay server completely.
- **Resilient**: Relays are reasonably resilient to external takeover and network traffic intercept. Such a takeover, if successful, only exposes message metadata, but not the content of any messages. Minor mis-configurations of a relay node, (such as leaking log files, etc.), during deployment by more casual users do not lead to a catastrophic breakdown of message privacy.
- **Private nodes**: Power users have the option to deploy their own personal relay nodes and have the ability to add them into the configuration of mobile applications that are reliant on this kind of p2p network.

## Test Dashboard
Each Zax deployment includes (via `/public`) a test [Dashboard](https://github.com/vault12/zax-dash) app, that uses [Glow](https://github.com/vault12/glow) to provide user-friend access point to given relay internal mailboxes. We maintain live [Test Server](https://zax-test.vault12.com) that runs our latest build. For testing purposes expiration on that relay is set for 30 minutes.

### Device-to-Device Messaging
Any device can communicate with any other device via Zax relays. The address space is global, and each device uses a hash of a long-term identity public key as the “address” in the global network of relays. Devices can generate as many keys as they need and implement [communication ratchet](https://github.com/vault12/glow/blob/master/src/rachetbox.coffee) protocols on the client level.

Clients start by sending a POST request to `/start_session` with a random token. The relay responds with a simple proof of work challenge based on that token. If the relay is configured for dynamic difficulty adjustment, the proof of work function will increase in difficulty as the relay experiences heavier load (thus increasing the client time required for a new session handshake and reducing load).

After answering the challenge to `/verify_session`, clients receive temporary session keys, and can start posting commands to `/command`. The command to relay is encrypted with session keys, while payload of command is usually encrypted with recipient public key, and is inaccessible to the relay. Using `upload`, `messageStatus`, `download` and `delete` commands, client devices can start sending end-to-end encrypted messages to each other.

Details of the protocol can be found in the [full technical spec](http://bit.ly/nacl_relay_spec). The full client library for messaging commands is implemented in the [Glow](https://github.com/vault12/glow/) library.


## <a name=“zax20”></a> Version 2.0 Updates
In Zax 2.0 we provide numerous stability and performance updates to the core codebase, and introduced new functionality of extending the Zax “dead drop” style communications to include file exchange.

- Codebase upgraded to `Ruby 2.4.1` and `Rails 5.1.3`
- New set of [commands](https://github.com/vault12/zax/wiki/Zax-2.0-File-Commands) for device-to-device exchange of large files
- Dynamic throttling option: when on, the relay session handshake “proof of work” function will grow harder with increased server load
- The companion [Glow](https://github.com/vault12/glow/) library detects failing relays and will pause connecting to them for a few hours
- Restart time window: optionally config time periods when supporting services are restarting, all workers will sleep during that window
- Improvements and optimizing for multi-worker/multi-threading access to Redis
- New logging details and easier to read color-coded logs
- Many performance improvements and bug fixes

#### <a name=“zax21”></a> 2.1 Updates

- *h2()* hash function zero-pad prefix increased to 64 bytes to match sha256 block
- Double JSON encoding removed in file commands
- Default session timeout increased to 20 minutes
- Client [Glow](https://github.com/vault12/glow) now supports command line interface

```
glow download [options] relay_url guest_public_key
  Options:
    -c, --count                  show number of messages without downloading them
    -d, --directory <directory>  directory to write downloaded file
    -f, --file <file>            file name to use instead of the original one
    -i, --interactive            interactive mode
    -k, --key                    set private key
    -n, --number <number>        max. number of files to download ("all" to download all)
    -p, --public                 show public key
    --silent                     silent mode
    --stdout                     stream output to stdout
    -h, --help                   output usage information
```

### File Exchange Cryptography
[File commands](https://github.com/vault12/zax/wiki/Zax-2.0-File-Commands) API leverages the existing anonymous message exchange mechanism of Zax relays to bootstrap file exchange metadata and key exchange. After parties have exchanged information about the file, new commands allow for the bulk content of an encrypted file to be exchanged.

Sending a file from Alice to Bob follows the following protocol:

- **Bootstrap**: Alice and Bob have to exchange their long term identity keys as the usual messaging bootstrap before communications via Zax relays. The Glow library [contains a sketch](https://github.com/vault12/glow/blob/master/tests/specs/07.invites.coffee) shows how such device-to-device initial key exchange might be implement in client apps. Read [technical specification](http://bit.ly/nacl_relay_spec) for the full details of that process. Before a file exchange takes place, we assume that Alice and Bob have already exchanged long term identity keys (`pkA` and `pkB`). The relay doesn’t store these public keys, and identifies Alice and Bob by the hash of public key as `hpkA` and `hpkB`
-  **Upload init**: Alice issues a `startFileUpload` command that contains the `hpk_to` address of Bob in a command data block. The data block also includes the metadata encrypted `pkA => pkB` using NaCl `crypto_box` so the whole metadata block is inaccessible to the Zax relay. That metadata block also includes the NaCl symmetric key for `crypto_secretbox` that will be used later to encrypt the file contents.
-  `startFileUpload` generates a regular Alice => Bob message on the relay, and can be downloaded by Bob with a regular `download` command. Alice receives the unique `uploadID` from the relay that is used for all subsequent commands about the given file. The relay response datablock include the maximum size of file chunk that clients can upload at once. Default is set to 100kb, but clients can modify that value in config, which will require appropriate changes to the size of the maximum POST command in the web server.
-   Internally, the relay stores the `uploadID` only in that initial `startFileUpload` message, stored in Bob’s mailbox (`hpk_to`) as a message from Alice (`hpk_from`). Once Bob or Alice deletes that message via the `delete` command or it expires as part of the regular redis expiration timeout, the relay will have no record of `uploadID` generated for the file. The relay uses either `secret_seed.txt` in `shared/uploads` or a config value to associate the `uploadID` given to clients and `storage_id` used by the relay to derive storage file names. If `secret_seed.txt`  is deleted there is no way to recover an association between files on the relay and client commands.
-   **Upload**: using the `uploadID` obtained from the relay, Alice can now issue the `uploadFileChunk` command, that requires that `uploadID`. In the command datablock, Alice provides the `nonce` used to encrypt this file chunk using the symmetric NaCl key for `crypto_secretbox`. Outside of the command datablock (encrypted as usual with the Alice=>Relay session key), the encrypted file contents produced by `secretbox` are posted as additional POST lines to the `uploadFileChunk` command.
-   The relay stores encrypted file chunks as local files in `shared\uploads` and derives a storage name from the `uploadID` and the local `secret_seed.txt` file. The nonce for each chunk is stored in redis and subject to the usual time expiration rules.
-   **Download**: Bob receives the `uploadID` and secret key for this file when it gets the initial `startFileUpload` message (by downloading it via the messaging family `download` command). Bob uses `uploadID` to issue `downloadFileChunk` commands to download the file chunk by chunk. It contains in its datablock (encrypted to Bob) the nonce of the given chunk, and the symmetrically encrypted chunk itself is the last line of the POST response to `downloadFileChunk` command.
-   **Status**: Either party can check information about files currently on the relay using their `uploadID` and `fileStatus` command. If the relay deleted or refreshed `secret_seed.txt` present during initial `startFileUpload` all requests for the old `uploadID` will fail.
-   **Delete**: Either party can delete the file using `uploadID` and the `deleteFile` command.
-   **Data pruning**: All redis information about the files expires, with the default set to one week. If a file is not removed with the `deleteFile` command, after redis expiration, the relay will delete old files via a cleanup job. The cleanup job will also delete files that have lost association with their storage id, which is the case if the `secret_seed.txt` is changed or deleted.
The full client library of [file commands](https://github.com/vault12/zax/wiki/Zax-2.0-File-Commands) is implemented in the [Glow](https://github.com/vault12/glow/) library.

## Getting Started
#### Redis
Zax requires [Redis](http://redis.io/) to run.
- via Brew: `brew install redis` and run `redis-server`
or
- [Download](https://redis.io/download) Redis
- [Build](https://github.com/antirez/redis#building-redis) Redis
- [Run](https://github.com/antirez/redis#running-redis) Redis

#### RVM
We suggest that you use the [Ruby Version Manager (RVM)](https://rvm.io/) to install Ruby and to build and install the gems you need to run Zax.

If you don't already have RVM installed, install it from [here](https://rvm.io).

#### Ruby
Zax requires at least version 2.4.1 of [Ruby](https://www.ruby-lang.org/) to run.

To check your Ruby version, type the following in a terminal:

```Shell
ruby -v
```

If you do not have version 2.4.1 or higher, then type the following in a terminal:
```Shell
rvm install 2.4.1
```

#### Installation
In a terminal, navigate to the directory in which you'd like to install Zax and type the following:

```Shell
# get the source
git clone git@github.com:vault12/zax.git

# create the gemset
cd zax
rvm use ruby-2.4.1
rvm gemset create zax
rvm gemset use zax

# run the installation script
gem install bundler
bundle install
```

If the 'bundle install' command fails with a message for libxml2 or Nokogiri, see the [Troubleshooting](#troubleshooting) section.

#### Running Zax

To bring up Zax run this command:

```Shell
rails s -p 8080
```

To make Zax accept connections from all hosts:

```Shell
rails s -p 8080 --binding=0.0.0.0
```

#### Testing Zax

To test groups of tests you can run any of these commands:

```Shell
rake test
rake test -v

rake test:controllers
rake test:integration
```

To run individual tests

```Shell
rake test test/integration/command_test.rb
rake test test/integration/command_test.rb -v
```

#### Troubleshooting

Zax uses [Nokogiri](http://www.nokogiri.org/tutorials/installing_nokogiri.html) which uses libxml2.
Here is an example installation via Brew on an OSX system:

```Shell
brew install libxml2
bundle config build.nokogiri --use-system-libraries
```

For other platforms than OSX, please consult:
[Installing Nokogiri]
(http://www.nokogiri.org/tutorials/installing_nokogiri.html)
for further instructions.

#### Example Command Line Utilities

```Shell
cd zax
mkdir tools
echo "*" > tools/.gitignore
echo "rvm gemset use zax" > tools/init
echo "# empty; prevent saving to disk" > tools/redis.conf
echo "redis-server ./tools/redis.conf" > tools/redis
echo "rails s -p 8080 --binding=0.0.0.0" > tools/relay
```

Then you can do e.g.:
```Shell
cd zax
. tools/init
. tools/relay
. tools/redis # new console window
```

## Demo
To see Glow and Zax in action, check out the [Live Demo](https://zax-test.vault12.com). This is a test project included in Zax called [Zax-Dash](https://github.com/vault12/zax-dash).

## Contributing
We encourage you to contribute to Zax using [pull requests](https://github.com/vault12/zax/pulls)! Please check out the [Contributing to Zax Guide](CONTRIBUTING.md) for guidelines about how to proceed.

## Slack Community [![Slack Status](https://slack.vault12.com/badge.svg)](https://slack.vault12.com)
We've set up a public slack community [Vault12 Dwellers](https://vault12dwellers.slack.com/). Request an invite by clicking [here](https://slack.vault12.com/).

## License
Zax is released under the [MIT License](http://opensource.org/licenses/MIT).

## Legal Reminder
Exporting/importing and/or use of strong cryptography software, providing cryptography hooks, or even just communicating technical details about cryptography software is illegal in some parts of the world. If you import this software to your country, re-distribute it from there or even just email technical suggestions or provide source patches to the authors or other people you are strongly advised to pay close attention to any laws or regulations which apply to you. The authors of this software are not liable for any violations you make - it is your responsibility to be aware of and comply with any laws or regulations which apply to you.
