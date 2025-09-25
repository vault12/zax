# Zax

<div align="center">
  <img src="https://user-images.githubusercontent.com/1370944/126783800-df5bcc0f-11c1-45c5-8e62-a960e787b111.jpg"
    alt="Zax">
</div>

<div align="center">
  <a href="https://github.com/vault12/zax/actions/workflows/ci.yml"><img src="https://github.com/vault12/zax/actions/workflows/ci.yml/badge.svg" alt="Github Actions Build Status" /></a>
  <a href="https://vault12.github.io/zax-dashboard/"><img src="https://img.shields.io/badge/demo-online-orange" alt="Demo Online" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="MIT License" /></a>
  <a href="http://makeapullrequest.com"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs welcome" /></a>
  <a href="https://twitter.com/_Vault12_"><img src="https://img.shields.io/twitter/follow/_Vault12_?label=Follow&style=social" alt="Follow" /></a>
</div>

Zax is a [NaCl-based Cryptographic Relay](https://s3-us-west-1.amazonaws.com/vault12/zax_infogfx.jpg), easily accessed via the [Glow](https://github.com/vault12/glow.ts) library. You can read the full [technical specification here](http://bit.ly/nacl_relay_spec).
Zax relay nodes are asynchronous "dead drops" for mobile communications. Relays are intended to be multiplied for reliability and form a distributed network. Individual devices send messages to a mutually deterministic subset of relays and check the same for response traffic.

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
Each Zax deployment includes (via `/public`) a test [Dashboard](https://github.com/vault12/zax-dashboard) app, that uses [Glow](https://github.com/vault12/glow.ts) client library to provide user-friend access point to given relay internal mailboxes. We maintain live [Test Server](https://zt.vault12.com) that runs our latest build. For testing purposes expiration on that relay is set for 30 minutes.

### Device-to-Device Messaging
Any device can communicate with any other device via Zax relays. The address space is global, and each device uses a hash of a long-term identity public key as the “address” in the global network of relays. Devices can generate as many keys as they need and implement [communication ratchet](https://github.com/vault12/glow/blob/master/src/rachetbox.coffee) protocols on the client level.

Clients start by sending a POST request to `/start_session` with a random token. The relay responds with a simple proof of work challenge based on that token. If the relay is configured for dynamic difficulty adjustment, the proof of work function will increase in difficulty as the relay experiences heavier load (thus increasing the client time required for a new session handshake and reducing load).

After answering the challenge to `/verify_session`, clients receive temporary session keys, and can start posting commands to `/command`. The command to relay is encrypted with session keys, while payload of command is usually encrypted with recipient public key, and is inaccessible to the relay. Using `upload`, `messageStatus`, `download` and `delete` commands, client devices can start sending end-to-end encrypted messages to each other.

> [!NOTE]
> Details of the protocol can be found in the [full technical spec](http://bit.ly/nacl_relay_spec). The full client library for messaging commands is implemented in the [Glow](https://github.com/vault12/glow.ts) library.

### File Exchange Cryptography
[File commands](https://github.com/vault12/zax/wiki/Zax-2.0-File-Commands) API leverages the existing anonymous message exchange mechanism of Zax relays to bootstrap file exchange metadata and key exchange. After parties have exchanged information about the file, new commands allow for the bulk content of an encrypted file to be exchanged.

Sending a file from Alice to Bob follows the following protocol:

- **Bootstrap**: Alice and Bob have to exchange their long term identity keys as the usual messaging bootstrap before communications via Zax relays. The Glow library [contains a sketch](https://github.com/vault12/glow/blob/master/tests/specs/07.invites.coffee) showing how such device-to-device initial key exchange might be implemented in client apps. Read [technical specification](http://bit.ly/nacl_relay_spec) for the full details of that process. Before a file exchange takes place, we assume that Alice and Bob have already exchanged long term identity keys (`pkA` and `pkB`). The relay doesn’t store these public keys, and identifies Alice and Bob by the hash of public key as `hpkA` and `hpkB`.
-  **Upload init**: Alice issues a `startFileUpload` command that contains the `hpk_to` address of Bob in a command data block. The data block also includes the metadata encrypted `pkA => pkB` using NaCl `crypto_box`, so the whole metadata block is inaccessible to the Zax relay. That metadata block also includes the NaCl symmetric key for `crypto_secretbox` that will be used later to encrypt the file contents.
-  `startFileUpload` generates a regular Alice => Bob message on the relay, and can be downloaded by Bob with a regular `download` command. Alice receives the unique `uploadID` from the relay that is used for all subsequent commands about the given file. The relay response data block includes the maximum size of file chunk that clients can upload at once. Default is set to 100kb, but clients can modify that value in config, which will require appropriate changes to the size of the maximum POST command in the web server configuration.
-   Internally, the relay stores `uploadID` only in that initial `startFileUpload` message, stored in Bob’s mailbox (`hpk_to`) as a message from Alice (`hpk_from`). Once Bob or Alice deletes that message via the `delete` command or it expires as a part of the regular Redis expiration timeout, the relay will have no record of `uploadID` generated for the file. The relay uses either `secret_seed.txt` in `shared/uploads` or a config value to associate the `uploadID` given to clients and `storage_id` used by the relay to derive storage file names. If `secret_seed.txt` is deleted, there is no way to recover an association between files on the relay and client commands.
-   **Upload**: using the `uploadID` obtained from the relay, Alice can now issue the `uploadFileChunk` command, that requires that `uploadID`. In the command datablock, Alice provides the `nonce` used to encrypt this file chunk using the symmetric NaCl key for `crypto_secretbox`. Outside of the command datablock (encrypted as usual with Alice => Relay session key), the encrypted file contents produced by `secretbox` are posted as additional POST lines to the `uploadFileChunk` command.
-   The relay stores encrypted file chunks as local files in `shared/uploads` and derives a storage name from the `uploadID` and the local `secret_seed.txt` file. The nonce for each chunk is stored in Redis and subject to the usual time expiration rules.
-   **Download**: Bob receives the `uploadID` and secret key for this file when it gets the initial `startFileUpload` message (by downloading it via the messaging family `download` command). Bob uses `uploadID` to issue `downloadFileChunk` commands to download the file chunk by chunk. It contains in its datablock (encrypted to Bob) the nonce of the given chunk, and the symmetrically encrypted chunk itself is the last line of the POST response to `downloadFileChunk` command.
-   **Status**: Either party can check information about files currently on the relay using their `uploadID` and `fileStatus` command. If the relay deletes or refreshes `secret_seed.txt` present during initial `startFileUpload`, all requests for the old `uploadID` will fail.
-   **Delete**: Either party can delete the file using `uploadID` and the `deleteFile` command.
-   **Data pruning**: All Redis information about the files expires, with the default set to one week. If a file is not removed with the `deleteFile` command, after Redis expiration, the relay will delete old files via a cleanup job. The cleanup job will also delete files that have lost association with their storage id, which is the case if the `secret_seed.txt` is changed or deleted.

> [!NOTE]
> The full client library of [file commands](https://github.com/vault12/zax/wiki/Zax-2.0-File-Commands) is implemented in the [Glow](https://github.com/vault12/glow.ts) library.

## Getting Started

### Prerequisites

#### Redis
Zax requires [Redis](http://redis.io/) to run.

**Option 1: Via Homebrew (macOS)**
```bash
brew install redis
redis-server
```

**Option 2: Manual Installation**
- [Download](https://redis.io/download) Redis
- [Build](https://github.com/redis/redis#building-redis) Redis
- [Run](https://github.com/redis/redis#running-redis) Redis

#### Sodium
```bash
brew install libsodium
```

#### Ruby Version Manager (RVM)
We suggest using the [Ruby Version Manager (RVM)](https://rvm.io/) to install Ruby and manage gems.

If you don't already have RVM installed:
```bash
# Install RVM
curl -sSL https://get.rvm.io | bash -s stable
```

#### Ruby
Zax requires at least **Ruby 3.2.0** and **RVM 1.29.10**.

**Check your Ruby version:**
```bash
ruby -v
```

**Install Ruby 3.2.0 if needed:**
```bash
rvm install 3.2.0
```

#### Installation
In a terminal, navigate to the directory in which you'd like to install Zax and type the following:

```Shell
# get the source
git clone https://github.com/vault12/zax.git

# create the gemset
cd zax
rvm use ruby-3.2.0
rvm gemset create zax
rvm gemset use zax

# run the installation script
gem install bundler
bundle install
```

If `bundle install` command fails with a message for libxml2 or Nokogiri, see the [Troubleshooting](#troubleshooting) section.

#### Running Zax

To bring up Zax run this command:

```Shell
rails s -p 8080
```

To make Zax accept connections from all hosts:

```Shell
rails s -p 8080 --binding=0.0.0.0
```

#### Deployment

For instructions on deploying a custom Zax relay node on [Digital Ocean](https://www.digitalocean.com), refer to [DEPLOYMENT.md](DEPLOYMENT.md).

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

For other platforms than OS X, please consult [Installing Nokogiri](http://www.nokogiri.org/tutorials/installing_nokogiri.html) for further instructions.

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
To see Glow and Zax in action, check out the [Live Demo](https://zt.vault12.com). This is a test project included in Zax called [Zax Dashboard](https://github.com/vault12/zax-dashboard).

## Contributing
We encourage you to contribute to Zax using [pull requests](https://github.com/vault12/zax/pulls)! Please check out the [Contributing to Zax Guide](CONTRIBUTING.md) for guidelines about how to proceed.

## Ecosystem

Project | Description
--- | ---
[Glow](https://github.com/vault12/glow.ts) | Client library for interacting with Zax Cryptographic Relay
[Zax Dashboard](https://github.com/vault12/zax-dashboard) | Sample dashboard app for Zax Cryptographic Relay
[TrueEntropy](https://github.com/vault12/TrueEntropy) | High volume thermal entropy generator

## License
Zax is released under the [MIT License](http://opensource.org/licenses/MIT).

## Legal Reminder
Exporting/importing and/or use of strong cryptography software, providing cryptography hooks, or even just communicating technical details about cryptography software is illegal in some parts of the world. If you import this software to your country, re-distribute it from there or even just email technical suggestions or provide source patches to the authors or other people you are strongly advised to pay close attention to any laws or regulations which apply to you. The authors of this software are not liable for any violations you make - it is your responsibility to be aware of and comply with any laws or regulations which apply to you.
