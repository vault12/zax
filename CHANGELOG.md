# Changelog

## [3.0.2] - 2025-09-25

- Upgraded Rails to the version 7.1.5.2
- Patched vulnerable dependencies

## [3.0.1] - 2024-09-23

- Upgraded Rails to version 7.0.8.4
- Added deployment instructions for a custom Zax relay node on [DigitalOcean](https://www.digitalocean.com)
- Updated to the latest versions of Zax Dashboard and refreshed other dependencies

## [3.0.0] - 2024-09-02

- Upgraded to Ruby 3.2
- Enhanced documentation and streamlined setup instructions
- Transitioned to GitHub Actions for continuous integration (CI)
- Adopted the latest versions of Zax Dashboard and updated other dependencies

## [2.2.1] - 2017-11-29

- Switched to the new version of Zax Dashboard and update dependencies

## [2.1.0] - 2017-11-29

- *h2()* hash function zero-pad prefix increased to 64 bytes to match sha256 block
- Double JSON encoding removed in file commands
- Default session timeout increased to 20 minutes
- [Glow](https://github.com/vault12/glow) now supports command line interface:

```
glow clean <relay_url> <guest_public_key>                delete all files in mailbox on the relay
glow count <relay_url> <guest_public_key> [options]      show number of pending files on the relay
glow download <relay_url> <guest_public_key> [options]   download file(s) from the relay
glow key [options]                                       show public key or h2(pk), set/update private key
glow help [cmd]                                          display help for [cmd]
```

## [2.0.0] - 2017-09-11

In Zax 2.0 we provide numerous stability and performance updates to the core codebase, and introduced new functionality of extending the Zax “dead drop” style communications to include file exchange.

- Codebase upgraded to `Ruby 2.4.1` and `Rails 5.1.3`
- New set of [commands](https://github.com/vault12/zax/wiki/Zax-2.0-File-Commands) for device-to-device exchange of large files
- Dynamic throttling option: when on, the relay session handshake “proof of work” function will grow harder with increased server load
- The companion [Glow](https://github.com/vault12/glow) library detects failing relays and will pause connecting to them for a few hours
- Restart time window: optionally config time periods when supporting services are restarting, all workers will sleep during that window
- Improvements and optimizing for multi-worker/multi-threading access to Redis
- New logging details and easier to read color-coded logs
- Many performance improvements and bug fixes