# Deploying Zax on a clean Ubuntu droplet — automated

[`install.sh`](install.sh) runs the whole
[DEPLOYMENT_MANUAL.md](DEPLOYMENT_MANUAL.md) sequence for you: it asks a
few questions, then installs and verifies everything on its own. The
script and the manual do the same things in the same order — read the
manual whenever you want to know what a step actually does.

## 0. Before you start

* The whole deploy takes about 10 minutes; the questions all come first,
  so you can answer them and walk away.
* Tested end-to-end on Ubuntu 26.04 LTS (DigitalOcean, July 2026).
* `zax.example.com` and `1.2.3.4` are the example hostname/IP — replace
  with yours.
* DigitalOcean and Cloudflare are simply what we test on: any VPS with
  plain Ubuntu works, and so does an un-proxied DNS record.

## 1. Create a droplet

DigitalOcean → _Create > Droplets_ → image: plain **Ubuntu 26.04 LTS x64**
(from the default OS list, not Marketplace) → authentication: **SSH Key**.
Note the assigned IP.

## 2. Point DNS at it

In Cloudflare add an `A` record: relay hostname → droplet IP, proxied
(orange cloud). The hostname resolves to Cloudflare edge, so always SSH by
IP.

## 3. Run the installer

```bash
ssh root@1.2.3.4
curl -fO https://raw.githubusercontent.com/vault12/zax/main/install.sh
bash install.sh
```

It asks a few questions — relay hostname, email for Let's Encrypt, an
optional Sentry DSN for error reports (Enter to skip; see the manual's
«Optional: Sentry error reporting»), repo URL (Enter for the public
repo), branch (Enter for `main`) — shows a summary and runs unattended.
Each step prints one `OK` line; the full transcript of every command
goes to `/var/log/zax-install.log`.

Already cloned the repo? `./install.sh` from inside the clone works the
same — the relay is installed into its own checkout under
`/home/zax/zax`, and the script reminds you at the end that the clone you
ran it from can be removed.

## What the script hardens

Besides installing, the script applies the small, universal hardening the
manual describes by hand — nothing that depends on Cloudflare,
DigitalOcean or a particular Ubuntu image:

* **nginx** (manual §8, «Hardening nginx»): no version in the `Server`
  header or on error pages; three browser headers that cannot break the
  page (nosniff, `X-Frame-Options DENY`, `Referrer-Policy`); and
  catch-all servers that give a connection without the relay's name
  nothing, not even a certificate. The certificate part needs nginx
  1.19.4 or newer; on an older release (Ubuntu 22.04 ships 1.18) the
  script keeps only the port-80 catch-all and says so in its log, and the
  bare address still presents the certificate.
* **Secrets** (§7): the Sentry DSN lives in the root-only `/etc/zax/env`,
  never in the world-readable unit file, and the file-store seed is made
  private to its owner.
* **SSH** («Generic droplet hygiene»): sshd offers only current
  cryptography and its ed25519 host key, with no Ubuntu build suffix in
  the banner. A client that had cached only the old ECDSA host key asks
  you to confirm the new one once; your own RSA or ECDSA login keys keep
  working.
* **Logs**: the relay's own log under `shared/log/` is rotated daily with
  a week kept; `journalctl -u zax` shows only service start and stop
  messages.

The last step checks, as before, that the relay answers through the real
DNS path; the outside checks for the hardening itself are in the
manual's §10.

## Optional: deploying from a private fork

Private repos deploy over ssh with a **read-only** deploy key. If you
have one, copy it to the droplet before running the script:

```bash
scp zax-deploy-key root@1.2.3.4:/root/
```

then answer the repo question with the ssh URL
(`git@github.com:you/your-fork.git`) and the key question with
`/root/zax-deploy-key`. The script moves the key to
`/home/zax/.ssh/id_ed25519` — nothing stays behind in `/root`.

No key at hand? Press Enter instead of a path: the script generates one
on the droplet, prints the public half and waits while you add it on
GitHub (**your fork → Settings → Deploy keys**, leave _Allow write
access_ unchecked).

## If a step fails

The failed step prints the error, the path to the full log and the
matching DEPLOYMENT_MANUAL.md section. Fix the cause and run
`bash install.sh` again — finished steps re-verify in seconds and the
install continues where it stopped (your previous answers are offered as
defaults). On a fresh droplet the other honest option is to destroy it
and start over: that costs ten minutes.

## Updating the relay

Re-run the script: it pulls the branch, rebuilds and restarts the relay.
Or do it by hand per the manual's «Updating the relay» section.
