# Zax [![Build Status](https://travis-ci.com/vault12/zax.svg?token=tByS6zUN7PTfiGk8KPRs&branch=master)](https://travis-ci.com/vault12/zax)

Zax is a [NaCl-based Cryptographic Relay](https://s3-us-west-1.amazonaws.com/vault12/zax_infogfx.jpg), easily accessed via the [Glow](https://github.com/vault12/glow) library. You can read the full [technical specification here](http://bit.ly/nacl_relay_spec).

## Features
- **Universal**: All Zax Relay nodes are mutually interchangeable and operate in a global address space. Any mobile device can contact any node to pass private messages to any other mobile device without a pre-existing setup or registration with that Relay.
- **Encrypted end-to-end**: It is cryptographically impossible for a Zax Relay node to decrypt the traffic passing though it between endpoint devices even if the Relay is taken over by an external agency.
- **Ephemeral**: Zax Relay nodes do not store anything in permanent storage, and operate only with *memory-based* ephemeral storage. The Relay acts as an encrypted memory cache shared between mobile devices. Key information is kept in memory only and erased within minutes after completing the session. Encrypted messages are kept in memory for future collection and are erased after a few days if not collected by the target device.
- **Well-known relays**: A deployed Zax Relay node's URL/identity should be well known and proven by a TLS certificate. Applications might implement certificate pinning for well-known relays of their choosing. A mobile app could keep a list of geographically dispersed relays and use a deterministic subset of them to send & receive asynchronous messages to/from another mobile device.
- **Identification privacy**: After establishing temporary keys for each session, a Zax Relay node never stores long-term identity keys of the endpoint devices. When the protocol requires the verification of public key ownership, these operations happen in memory only and are immediately erased afterward. In the future, we're planning on leveraging Zero Knowledge Proofs to eliminate disclosure of long term public keys (and therefore device identity) to a Zax Relay server completely.
- **Resilient**: Relays are reasonably resilient to external takeover and network traffic intercept. Such a takeover, if successful, only exposes message metadata, but not the content of any messages. Minor mis-configurations of a relay node, (such as leaking log files, etc.), during deployment by more casual users do not lead to a catastrophic breakdown of message privacy.
- **Private nodes**: Power users have the option to deploy their own personal relay nodes and have the ability to add them into the configuration of mobile applications that are reliant on this kind of p2p network.

## Test Dashboard
Each Zax deployment includes (via `/public`) a test [Dashboard](https://github.com/vault12/zax-dash) app, that uses [Glow](https://github.com/vault12/glow) to provide user-friend access point to given relay internal mailboxes. We maintain live [Test Server](https://zax_test.vault12.com) that runs our latest build. For testing purposes expiration on that relay is set for 30 minutes.

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
Zax requires at least version 2.2.3 of [Ruby](https://www.ruby-lang.org/) to run.

To check your Ruby version, type the following in a terminal:

```Shell
ruby -v
```

If you do not have version 2.2.3 or higher, then type the following in a terminal:
```Shell
rvm install 2.2.3
```

#### Installation
In a terminal, navigate to the directory in which you'd like to install Zax and type the following:

```Shell
# get the source
git clone git@github.com:vault12/zax.git

# create the gemset
cd zax
rvm use ruby-2.2.3
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

## Demo
To see Glow and Zax in action, check out the [Live Demo](https://zax_test.vault12.com). This is a test project included in Zax called [Zax-Dash](https://github.com/vault12/zax-dash).

## Contributing
We encourage you to contribute to Zax using [pull requests](https://github.com/vault12/zax/pulls)! Please check out the [Contributing to Zax Guide](CONTRIBUTING.md) for guidelines about how to proceed.

## Slack Community [![Slack Status](https://slack.vault12.com/badge.svg)](https://slack.vault12.com)
We've set up a public slack community [Vault12 Dwellers](https://vault12dwellers.slack.com/). Request an invite by clicking [here](https://slack.vault12.com/).

## License
Zax is released under the [MIT License](http://opensource.org/licenses/MIT).

## Legal Reminder
Exporting/importing and/or use of strong cryptography software, providing cryptography hooks, or even just communicating technical details about cryptography software is illegal in some parts of the world. If you import this software to your country, re-distribute it from there or even just email technical suggestions or provide source patches to the authors or other people you are strongly advised to pay close attention to any laws or regulations which apply to you. The authors of this software are not liable for any violations you make - it is your responsibility to be aware of and comply with any laws or regulations which apply to you.
