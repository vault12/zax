# Deploying Zax on a clean Ubuntu droplet

## 0. Before you start

* The whole deploy takes about 10 minutes — Ruby comes as a prebuilt static
  binary via [rv](https://github.com/spinel-coop/rv) (made by the
  maintainers of Bundler, RubyGems and rbenv), nothing is compiled except a
  couple of native gems.
* Tested end-to-end on Ubuntu 26.04 LTS (DigitalOcean, July 2026).
* `zax.example.com` and `1.2.3.4` are the example hostname/IP — replace
  with yours.
* DigitalOcean and Cloudflare are simply what we test on: any VPS with
  plain Ubuntu works, and so does an un-proxied DNS record — the
  Cloudflare-specific notes then just don't apply.

## 1. Create a droplet

DigitalOcean → _Create > Droplets_ → image: plain **Ubuntu 26.04 LTS x64**
(from the default OS list, not Marketplace) → authentication: **SSH Key**.
Note the assigned IP.

## 2. Point DNS at it

In Cloudflare add an `A` record: relay hostname → droplet IP, proxied
(orange cloud). The hostname resolves to Cloudflare edge, so always SSH by
IP:

```bash
ssh root@1.2.3.4
```

## 3. Install packages

```bash
apt update
apt install -y curl build-essential libyaml-dev libsodium-dev \
  nginx redis-server certbot python3-certbot-nginx npm
```

Why each: `curl` fetches the rv installer; `build-essential` +
`libyaml-dev` build the native gems (all other headers ship inside the
static Ruby); `libsodium-dev` is the runtime for all NaCl crypto; `npm`
fetches the zax-dashboard package; the rest is the serving stack. apt
silently skips anything already installed.

If apt fails with "Could not get lock" the droplet's first-boot auto-update
is still running — wait a few minutes and retry.

Redis needs no configuration: Ubuntu starts and enables it on install,
listening on localhost only. Check: `redis-cli ping` → `PONG`.

## 4. Create the app user

The relay runs as an unprivileged user:

```bash
adduser --disabled-password --gecos "" zax
```

## 5. Install Ruby with rv

Ubuntu's packaged Ruby is 3.3 and the repo needs 3.4. [rv](https://github.com/spinel-coop/rv)
installs a prebuilt, statically-linked Ruby in seconds — no compilation. As
the `zax` user:

```bash
su - zax
curl -LsSf https://github.com/spinel-coop/rv/releases/latest/download/rv-installer.sh | sh
. ~/.cargo/env
rv ruby install 3.4.10
ln -s ~/.local/share/rv/rubies/ruby-3.4.10 ~/ruby
echo 'export PATH="$HOME/ruby/bin:$PATH"' >> ~/.profile
exit
su - zax -c 'ruby -v'    # ruby 3.4.10
```

The `~/ruby` symlink is the only place the exact Ruby version lives:
everything below points at `~/ruby/bin` and survives version upgrades.

## 6. Clone and install Zax

```bash
su - zax
git clone https://github.com/vault12/zax.git
cd zax
./install_dependencies.sh      # bundle install + npm install + populate public/
exit
```

### Optional: deploying a branch

The clone above deploys `main`. For anything else: `git checkout <branch>`
after the clone, before `./install_dependencies.sh`.

### Optional: deploying from a private fork

The public clone above needs no credentials; a private repo does — the
droplet gets its own **read-only** deploy key, generated right here (the
private half never leaves the machine). As `zax`, generate a key (accept the
default path, empty passphrase) and print the public part:

```bash
ssh-keygen -t ed25519
cat ~/.ssh/id_ed25519.pub
```

Add the printed key on GitHub (needs a repo admin): **your fork → Settings →
Deploy keys → Add deploy key**, title it after the host, leave _Allow write
access_ **unchecked**. Then clone over ssh (answer `yes` to the one-time
host-key prompt) — into the same folder name, so the rest of this doc
applies unchanged:

```bash
git clone git@github.com:vault12/zax_private.git zax
```

Per-machine keys mean a compromised box burns only its own key; when a
droplet is destroyed, delete its key on GitHub.

## 7. Run Zax as a systemd service

`/etc/systemd/system/zax.service`:

```ini
[Unit]
Description=Zax relay (puma)
Wants=redis-server.service
After=network.target redis-server.service

[Service]
User=zax
WorkingDirectory=/home/zax/zax
Environment=RAILS_ENV=production
Environment=RAILS_LOG_TO_STDOUT=1
Environment=ZAX_HOST=zax.example.com
EnvironmentFile=-/etc/zax/env
Environment=PATH=/home/zax/ruby/bin:/usr/bin:/bin
ExecStart=/home/zax/ruby/bin/bundle exec puma -b tcp://127.0.0.1:8080 -e production
UMask=0077
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

`ZAX_HOST` is the relay's public hostname — Rails host authorization admits
only it. The `Environment=PATH=` line is required — without it `bundle exec`
cannot find gem executables and the service crash-loops with
"bundler: command not found: puma".

`EnvironmentFile=-/etc/zax/env` is where secrets go (the `-` means the
file may be absent). Unit files are world-readable and `systemctl show`
prints their `Environment=` lines to any account on the box, so nothing
secret belongs in the unit itself. Create the file root-only, even if it
stays empty for now:

```bash
install -d /etc/zax && touch /etc/zax/env && chmod 600 /etc/zax/env
systemctl daemon-reload
systemctl enable --now zax
systemctl status zax
```

A direct `curl http://127.0.0.1:8080/` answers **403** — that's host
authorization at work; requests through nginx carry the right `Host` header.

On first boot the relay creates `shared/uploads/secret_seed.txt` — stored
file names derive from it. Back it up once uploads are in use: losing it
orphans all uploaded files. `UMask=0077` in the unit makes it, and every
other file the relay creates, private to its owner from the start; a seed
created under an older unit may still be world-readable, so as `zax`:

```bash
chmod 600 ~/zax/shared/uploads/secret_seed.txt
```

### Optional: Sentry error reporting

The relay can report its own failures (unexpected exceptions, Redis
trouble) and count the requests it rejects in [Sentry](https://sentry.io).
Create a Rails project there, copy its DSN (project → Settings → Client
Keys) and put one line into the root-only `/etc/zax/env`:

```ini
SENTRY_DSN=https://<key>@<host>/<project-id>
```

then `systemctl restart zax` (the file is read at start; no
`daemon-reload` needed). Without this line nothing is ever sent anywhere. Failures show up as Sentry errors,
rejections under Explore → Metrics and Explore → Logs, labelled with the
`ZAX_HOST` hostname.

<details>
<summary>What exactly leaves the relay</summary>

* Relay-side failures go out as errors. Protocol violations from clients
  never do — anyone on the internet can produce those at will.
* Every 4xx a controller answers adds one point to the `relay.rejection`
  metric with the HTTP status, the reason (`RateLimit`, `QuotaExceeded`, `NoSession`,
  `ClockSkew`, ... — the relay's own names, see `ZaxError#reason`), its
  kind (`limit`, `device`, `session` or `malformed`), the route, the
  command and a 16-character hash of the sender's key. Never the key
  itself, the request body or the client address. Answers that never
  reach a controller are not counted: the 403 of host authorization and
  nginx's 413.
* The sender is named only once the request has proved it holds the
  session (its command decrypted). A rejection before that point — a
  request for a session that has ended, say — carries no sender, so nobody
  can put rejections on another device's record by quoting its key.
* The hash is keyed with the relay's file-store seed (`secret_seed.txt`):
  stable for the life of the relay, not matchable against a list of public
  keys, different on every relay unless they share `ZAX_SECRET_SEED`. A
  relay without a file store keys it with `SECRET_KEY_BASE`, or with a
  per-boot random value when that is not set.
* Named rejections also get a log line for the device's timeline, at most
  ten per sender per minute (`config.x.relay.rejection_log_cap`). The
  metric counts every rejection.

</details>

## 8. Put nginx in front

`/etc/nginx/sites-available/zax`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name zax.example.com;
    client_max_body_size 4m;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
rm /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/zax /etc/nginx/sites-enabled/zax
nginx -t && systemctl reload nginx
```

### Hardening nginx

Three small things, all outside the site file so certbot's later rewrite
of it never touches them.

**No version anywhere.** Ubuntu ships `server_tokens build;` in
`nginx.conf`, which prints `nginx/1.28.3 (Ubuntu)` in the `Server` header
and in the footer of nginx's own error pages (a 413 on an oversized
upload, say — and those pages pass through Cloudflare unchanged, even
though the header itself does not). Edit the line in place; a second copy
in `conf.d` would be a duplicate-directive error:

```bash
sed -i -E 's/^(\s*)#?\s*server_tokens\s.*/\1server_tokens off;/' /etc/nginx/nginx.conf
```

**Three browser headers that cannot break the page.**
`/etc/nginx/conf.d/zax-headers.conf`:

```nginx
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options DENY always;
add_header Referrer-Policy no-referrer always;
```

None of the three restricts what the dashboard loads, which is why there
is no Content-Security-Policy here: the dashboard package is pulled by
version range, so a policy fixed in nginx would break on a dashboard
release without any change on the relay, and show it only in the browser
console. HSTS is set by Cloudflare at the edge. One rule to keep:
`add_header` does not stack, so one inside the site's `server` or
`location` blocks silently discards this set for that block — keep the
site file free of it. The relay's own headers (`Access-Control-*`,
`X-Error-Details`, `Retry-After`) come from Rails and pass through; the
clients depend on them.

**The bare address says nothing.** Without this, anyone connecting to the
droplet's IP gets the relay's certificate (which names the hostname, and
certificate scanners index that) and a 403 that confirms a relay is
there. `/etc/nginx/conf.d/zax-default.conf`:

```nginx
server { listen 80 default_server; listen [::]:80 default_server; server_name _; return 444; }
server { listen 443 ssl default_server; listen [::]:443 ssl default_server; server_name _; ssl_reject_handshake on; }
```

Connections without the relay's name get the TLS handshake refused, or
the connection closed without a byte on port 80; nothing else changes,
because requests that carry the hostname still match the site block.
`ssl_reject_handshake` needs nginx 1.19.4 or later: Ubuntu 22.10 and
newer have it, but 22.04 ships nginx 1.18, so there leave the 443 line
out — `nginx -t` would reject it — and accept that the bare address still
presents the certificate; the port-80 half applies either way. The
installer makes the same choice by version.

```bash
nginx -t && systemctl reload nginx
```

## 9. Get a TLS certificate

```bash
certbot --nginx -d zax.example.com
```

Answer the prompts (email, agree to terms). It works straight through the
Cloudflare proxy, rewrites the nginx config for 443 and renews itself via a
systemd timer. Until this step the Cloudflare edge answers `521` for the
host; after it — `502` if the app is down, `200` when everything runs.

## 10. Verify the relay

From your machine, through Cloudflare:

```bash
# dashboard:
curl -s -o /dev/null -w "%{http_code}\n" https://zax.example.com/    # 200

# relay handshake — expect the relay token and PoW difficulty back, e.g.
#   Ly3d4tQNuci+G+RBTUxhIipEaQqGNUOLTTbr4JAEJws=
#   2
head -c32 /dev/urandom | base64 | curl -s --data @- https://zax.example.com/start_session
```

Alternatively, just open `https://zax.example.com` in a browser — a loaded
dashboard is the same check as the first curl.

And the hardening, from your machine:

```bash
curl -sI https://zax.example.com/ | grep -iE 'x-frame-options|x-content-type|referrer'   # the three headers
curl -sk -m 8 https://1.2.3.4/           # fails: handshake refused, no certificate
ssh-audit 1.2.3.4                        # no warnings (pip install ssh-audit)
```

## Updating the relay

A relay update is a pull plus restart:

```bash
su - zax
cd zax
git pull
./install_dependencies.sh
exit
systemctl restart zax
```

If the new release wants a newer Ruby (see `.ruby-version` in the repo): as
`zax`, `rv ruby install <version>`, re-point the symlink with
`ln -sfn ~/.local/share/rv/rubies/ruby-<version> ~/ruby`, then restart.

## Generic droplet hygiene

Not zax-specific — standard things for any fresh VPS, do them at any point.

* **Firewall.** Plain Ubuntu ships with ufw inactive:

```bash
ufw limit OpenSSH
ufw allow "Nginx Full"
ufw enable
```

Answer `y` to the ssh warning: the first rule already allows SSH (and
rate-limits it against brute force).

* **SSH cryptography.** Ubuntu's OpenSSH defaults are modern, but still
  offer NIST-curve key exchanges, an ECDSA host key and SHA-1 MACs as
  fallbacks, and `ssh-audit` (a standard bounty tool) files every one of
  them. `/etc/ssh/sshd_config.d/10-zax.conf` removes them — the lists are
  subtractive, so they take away what matches from the defaults and error
  on nothing — and drops the Ubuntu build suffix from the banner:

```
HostKey /etc/ssh/ssh_host_ed25519_key
KexAlgorithms -ecdh-sha2-nistp*,diffie-hellman-*
MACs -hmac-sha1*,umac-64*,umac-128@openssh.com,hmac-sha2-256,hmac-sha2-512
HostKeyAlgorithms -ecdsa-*,*rsa*,sk-ecdsa*
DebianBanner no
```

```bash
sshd -t && systemctl restart ssh
```

  Existing sessions survive the restart. sshd now offers only its ed25519
  host key: a client that had cached only the old ECDSA key asks you to
  confirm the new one once. This is the host's key; your own RSA or ECDSA
  login keys keep working, since the list of accepted user keys is untouched.

* **Logs.** Ubuntu rotates nginx, syslog and Redis logs on its own and
  caps the journal at 4 GB. The relay's own log is the exception: puma
  redirects the app's output into `shared/log/puma.stdout.log`
  (`journalctl -u zax` shows only service start and stop messages), and
  nothing rotates that file. It grows about a megabyte a day on a quiet
  relay and holds the request record, so `/etc/logrotate.d/zax`:

```
/home/zax/zax/shared/log/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su zax zax
}
```

  `copytruncate` because puma keeps the file open and appends; `su`
  because logrotate refuses to work in a directory writable by a
  non-root user otherwise. Check with `logrotate -d /etc/logrotate.d/zax`.
