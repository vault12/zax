#!/bin/bash
#
# Zax relay installer for a clean Ubuntu droplet.
#
# Automates the DEPLOYMENT_MANUAL.md sequence end to end: asks a few
# questions up front, then runs unattended. Safe to re-run at any time —
# every step converges, so a re-run resumes after a failure and also
# updates an already-installed relay. Run as root.

set -u -o pipefail

readonly LOG=/var/log/zax-install.log
readonly CONF=/etc/zax-install.conf
readonly APP_USER=zax
readonly APP_HOME=/home/zax
readonly APP_DIR=$APP_HOME/zax
readonly KEY_FILE=$APP_HOME/.ssh/id_ed25519
readonly UNIT_FILE=/etc/systemd/system/zax.service
readonly NGINX_SITE=/etc/nginx/sites-available/zax
readonly NGINX_HEADERS=/etc/nginx/conf.d/zax-headers.conf
readonly NGINX_DEFAULT=/etc/nginx/conf.d/zax-default.conf
readonly ENV_FILE=/etc/zax/env
readonly SSHD_CONF=/etc/ssh/sshd_config.d/10-zax.conf
readonly LOGROTATE_CONF=/etc/logrotate.d/zax
readonly DEFAULT_REPO=https://github.com/vault12/zax.git
readonly DEFAULT_BRANCH=main
readonly MANUAL=DEPLOYMENT_MANUAL.md

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------- output --

STEP_NO=0
readonly STEP_TOTAL=10

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Run one step: a single OK line on the terminal, the full command
# transcript in $LOG. On failure: the log tail, the log path and the
# matching manual section, then exit — a re-run continues from here.
run_step() { # run_step "description" "manual section" step_function
  local desc=$1 section=$2 fn=$3 started rc elapsed
  STEP_NO=$((STEP_NO + 1))
  printf '[%d/%d] %s ... ' "$STEP_NO" "$STEP_TOTAL" "$desc"
  printf '\n===== [%d/%d] %s — %s =====\n' \
    "$STEP_NO" "$STEP_TOTAL" "$desc" "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" >>"$LOG"
  started=$SECONDS
  ( set -ex; "$fn" ) >>"$LOG" 2>&1
  rc=$?
  elapsed=$((SECONDS - started))
  if [ "$rc" -eq 0 ]; then
    say "OK (${elapsed}s)"
    return 0
  fi
  say "FAILED (exit $rc)"
  say ""
  say "--- last lines of $LOG ---"
  tail -n 25 "$LOG"
  say "--------------------------"
  say ""
  say "Step [$STEP_NO/$STEP_TOTAL] «$desc» failed; full transcript: $LOG"
  say "The same ground is covered in $MANUAL, section «$section»."
  say "Fix the cause and run this script again — finished steps re-verify"
  say "in seconds and the install continues from this one."
  exit 1
}

# --------------------------------------------------------------- prompts --

ask() { # ask VAR "question" "default" — empty default means required
  local var=$1 q=$2 def=${3-} reply
  if [ -n "$def" ]; then
    read -r -p "$q [$def]: " reply
    printf -v "$var" '%s' "${reply:-$def}"
  else
    while true; do
      read -r -p "$q: " reply
      [ -n "$reply" ] && break
    done
    printf -v "$var" '%s' "$reply"
  fi
}

confirm() { # yes by default
  local reply
  read -r -p "$1 [Y/n]: " reply
  case ${reply:-y} in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# Display form of a DSN: enough to verify a paste (key prefix, host,
# project id), not enough to reuse the key. Config and unit get the full value.
mask_dsn() {
  printf '%s' "$1" | sed -E 's#^(https://[A-Za-z0-9]{6})[A-Za-z0-9]*@#\1…@#'
}

# probe_repo URL BRANCH [KEYFILE] — sets PROBE_RC / PROBE_OUT.
# rc != 0: can't access the repo; rc == 0 with empty output: no such branch.
probe_repo() {
  local url=$1 branch=$2 key=${3-}
  local sshcmd="ssh -o StrictHostKeyChecking=accept-new"
  [ -n "$key" ] && sshcmd="$sshcmd -i $key -o IdentitiesOnly=yes"
  PROBE_OUT=$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$sshcmd" \
    git ls-remote --heads "$url" "refs/heads/$branch" 2>&1)
  PROBE_RC=$?
}

# ------------------------------------------------------------- preflight --

[ "$(id -u)" -eq 0 ] || die "run as root — the script installs packages and services"
touch "$LOG" && chmod 600 "$LOG"

. /etc/os-release 2>/dev/null || true
if [ "${VERSION_ID-}" != "26.04" ]; then
  say "Warning: tested on Ubuntu 26.04 LTS, this is ${PRETTY_NAME:-an unknown system}."
  confirm "Continue anyway?" || exit 1
fi

# ------------------------------------------------------------- questions --

# Answers from a previous run become the defaults.
[ -f "$CONF" ] && . "$CONF"

say "Zax relay installer — a few questions, then everything runs on its own."
say "Full transcript of every command: $LOG"
say ""

while true; do
  ask HOST "Relay hostname (the public DNS name of this droplet)" "${HOST-}"
  printf '%s' "$HOST" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' && break
  say "That does not look like a hostname."
  HOST=""
done
if ! getent hosts "$HOST" >/dev/null; then
  say "Warning: $HOST does not resolve yet — the TLS step will fail until DNS is in place."
  confirm "Continue anyway?" || exit 1
fi

while true; do
  ask EMAIL "Email for Let's Encrypt (expiry notices)" "${EMAIL-}"
  case $EMAIL in *@*) break ;; *) say "That does not look like an email." ;; esac
done

# Optional per-relay error telemetry; with no DSN the relay reports nothing.
# A DSN put into the environment file by hand (see the manual) is the default.
SENTRY_DSN=${SENTRY_DSN-}
[ -n "$SENTRY_DSN" ] || [ ! -f "$ENV_FILE" ] || SENTRY_DSN=$(sed -n 's/^SENTRY_DSN=//p' "$ENV_FILE")
while true; do
  read -r -p "Sentry DSN for error reports (Enter to skip)${SENTRY_DSN:+ [$(mask_dsn "$SENTRY_DSN")]}: " reply
  SENTRY_DSN=${reply:-$SENTRY_DSN}
  [ -z "$SENTRY_DSN" ] && break
  printf '%s' "$SENTRY_DSN" | grep -Eq '^https://[A-Za-z0-9]+@[A-Za-z0-9.-]+(:[0-9]+)?/[0-9]+$' && break
  say "That does not look like a Sentry DSN (expected https://key@host/id)."
  SENTRY_DSN=""
done

GIT_KEY=""
while true; do
  ask REPO "Zax repo to deploy (ssh URL for private forks)" "${REPO:-$DEFAULT_REPO}"
  ask BRANCH "Branch" "${BRANCH:-$DEFAULT_BRANCH}"
  case $REPO in *[!A-Za-z0-9@:/._~-]*)
    say "Unexpected characters in the repo URL."; continue ;;
  esac
  case $BRANCH in *[!A-Za-z0-9/._-]*)
    say "Unexpected characters in the branch name."; continue ;;
  esac

  case $REPO in git@*|ssh://*)
    # An ssh URL means a private repo: it needs a read-only deploy key.
    if [ -f "$KEY_FILE" ]; then
      GIT_KEY=$KEY_FILE
      say "Using the deploy key already installed at $KEY_FILE."
    elif [ -z "$GIT_KEY" ]; then
      say ""
      say "A private repo is cloned with a read-only deploy key. If you have"
      say "one, copy it to this droplet first (scp mykey root@this-ip:/root/)"
      say "and give its path here; press Enter to generate a fresh key instead."
      read -r -p "Path to an existing private key [generate new]: " GIT_KEY
      if [ -n "$GIT_KEY" ] && [ ! -f "$GIT_KEY" ]; then
        say "No file at $GIT_KEY."
        GIT_KEY=""
        continue
      fi
      if [ -z "$GIT_KEY" ]; then
        GIT_KEY=/root/zax-deploy-key.tmp
        [ -f "$GIT_KEY" ] || ssh-keygen -t ed25519 -N "" -q -f "$GIT_KEY" -C "zax-relay-$HOST"
        say ""
        say "Add this public key on GitHub — repo → Settings → Deploy keys,"
        say "leave «Allow write access» unchecked, title it after the host:"
        say ""
        cat "$GIT_KEY.pub"
        say ""
        read -r -p "Press Enter when it is added ... " _
      fi
    fi ;;
  esac

  if ! command -v git >/dev/null; then
    say "(git is not installed yet — the repo and branch will be checked at clone time)"
    break
  fi
  probe_repo "$REPO" "$BRANCH" "$GIT_KEY"
  if [ "$PROBE_RC" -ne 0 ]; then
    case $REPO in
      https://github.com/*)
        SSH_FORM=$(printf '%s' "$REPO" | sed -E 's#^https://github.com/#git@github.com:#; s#(\.git)?$#.git#')
        say "Cannot read $REPO anonymously — the repo is private or the URL is wrong."
        if confirm "Private repos deploy over ssh with a deploy key. Use $SSH_FORM?"; then
          REPO=$SSH_FORM
        fi
        ;;
      git@*|ssh://*)
        say "GitHub did not accept the key, or the URL is wrong:"
        printf '%s\n' "$PROBE_OUT" | tail -n 3
        say "(a key added on GitHub can take a few seconds to become active)"
        if [ -n "$GIT_KEY" ] && [ -f "$GIT_KEY.pub" ]; then
          say "The public key again, in case it is not on GitHub yet:"
          say ""
          cat "$GIT_KEY.pub"
          say ""
        fi
        confirm "Retry with the same key?" || GIT_KEY=""
        ;;
      *)
        say "Cannot reach $REPO:"
        printf '%s\n' "$PROBE_OUT" | tail -n 3
        ;;
    esac
    continue
  fi
  if [ -z "$PROBE_OUT" ]; then
    say "The repo is reachable but has no branch «$BRANCH»."
    continue
  fi
  break
done

say ""
say "Ready to install:"
say "  relay:   https://$HOST"
say "  repo:    $REPO ($BRANCH)"
[ -n "$GIT_KEY" ] && [ "$GIT_KEY" != "$KEY_FILE" ] && \
  say "  key:     $GIT_KEY (will be moved to $KEY_FILE)"
[ -n "$SENTRY_DSN" ] && say "  sentry:  $(mask_dsn "$SENTRY_DSN")"
say "  certbot: $EMAIL — agrees to the Let's Encrypt Terms of Service"
confirm "Proceed?" || exit 1
say ""

# Saved answers become the defaults of the next run.
printf 'HOST=%q\nEMAIL=%q\nREPO=%q\nBRANCH=%q\nSENTRY_DSN=%q\n' \
  "$HOST" "$EMAIL" "$REPO" "$BRANCH" "$SENTRY_DSN" >"$CONF"
chmod 600 "$CONF"

# ----------------------------------------------------------------- steps --

step_packages() { # manual §3
  apt-get -o DPkg::Lock::Timeout=300 update
  apt-get -o DPkg::Lock::Timeout=300 install -y curl build-essential \
    libyaml-dev libsodium-dev nginx redis-server certbot \
    python3-certbot-nginx npm
  redis-cli ping | grep -q PONG
}

step_user() { # manual §4
  id -u "$APP_USER" 2>/dev/null || adduser --disabled-password --gecos "" "$APP_USER"
}

step_clone() { # manual §6 (clone half)
  if [ -n "$GIT_KEY" ] && [ "$GIT_KEY" != "$KEY_FILE" ]; then
    install -d -m 700 -o "$APP_USER" -g "$APP_USER" "$APP_HOME/.ssh"
    # mv, not cp: no stray private key left behind in /root
    mv "$GIT_KEY" "$KEY_FILE"
    rm -f "$GIT_KEY.pub"
    chown "$APP_USER:$APP_USER" "$KEY_FILE"
    chmod 600 "$KEY_FILE"
  fi
  if [ -d "$APP_DIR/.git" ]; then
    su - "$APP_USER" -c "cd zax &&
      git remote set-url origin '$REPO' &&
      GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new' git fetch origin &&
      git checkout '$BRANCH' &&
      GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new' git pull --ff-only origin '$BRANCH'"
  else
    su - "$APP_USER" -c "
      GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new' git clone '$REPO' zax &&
      cd zax && git checkout '$BRANCH'"
  fi
}

step_ruby() { # manual §5 — version comes from the repo, not from this script
  local ver
  ver=$(tr -d '[:space:]' <"$APP_DIR/.ruby-version")
  # "ruby-3.4.10" is a valid .ruby-version spelling of "3.4.10"
  ver=${ver#ruby-}
  # interpolated into the su heredoc below — accept only a version number
  if ! printf '%s' "$ver" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    echo "unexpected .ruby-version content: «$ver»"
    return 1
  fi
  su - "$APP_USER" <<RUBY
set -ex
if [ ! -x "\$HOME/.cargo/bin/rv" ]; then
  curl -LsSf https://github.com/spinel-coop/rv/releases/latest/download/rv-installer.sh | sh
fi
. "\$HOME/.cargo/env"
# .ruby-version may be fuzzy ("3.4"): rv resolves it to the newest patch
# release, so locate the actual install directory by glob, newest last.
rubies="\$HOME/.local/share/rv/rubies"
have=\$(ls -d "\$rubies/ruby-$ver" "\$rubies/ruby-$ver".* 2>/dev/null | sort -V | tail -n 1)
if [ -z "\$have" ]; then
  rv ruby install "$ver"
  have=\$(ls -d "\$rubies/ruby-$ver" "\$rubies/ruby-$ver".* 2>/dev/null | sort -V | tail -n 1)
fi
[ -d "\$have" ]
ln -sfn "\$have" "\$HOME/ruby"
grep -qF 'ruby/bin' "\$HOME/.profile" || echo 'export PATH="\$HOME/ruby/bin:\$PATH"' >>"\$HOME/.profile"
RUBY
  su - "$APP_USER" -c 'ruby -v' | grep -F "$ver"
}

step_bundle() { # manual §6 (install half)
  su - "$APP_USER" -c 'cd zax && ./install_dependencies.sh'
}

step_service() { # manual §7
  # Secrets live in a root-only environment file, never in the unit: unit
  # files are world-readable and «systemctl show» echoes them to any account.
  # Only the SENTRY_DSN line is ours: anything an operator added by hand
  # survives a re-run, and so does a hand-added DSN when this run gave none.
  install -d -m 755 /etc/zax
  local keep=""
  if [ -f "$ENV_FILE" ]; then
    if [ -n "$SENTRY_DSN" ]; then keep=$(grep -vE '^(#|SENTRY_DSN=)' "$ENV_FILE" || true)
    else keep=$(grep -v '^#' "$ENV_FILE" || true); fi
  fi
  # written under umask 077, so the file is never world-readable, not even for an instant
  ( umask 077; printf '%s\n' '# managed by install.sh — environment of zax.service; keep it root-only' \
    ${SENTRY_DSN:+"SENTRY_DSN=$SENTRY_DSN"} ${keep:+"$keep"} >"$ENV_FILE.tmp" )
  mv "$ENV_FILE.tmp" "$ENV_FILE"
  cat >"$UNIT_FILE" <<UNIT
[Unit]
Description=Zax relay (puma)
Wants=redis-server.service
After=network.target redis-server.service

[Service]
User=$APP_USER
WorkingDirectory=$APP_DIR
Environment=RAILS_ENV=production
Environment=RAILS_LOG_TO_STDOUT=1
Environment=ZAX_HOST=$HOST
EnvironmentFile=-$ENV_FILE
Environment=PATH=$APP_HOME/ruby/bin:/usr/bin:/bin
ExecStart=$APP_HOME/ruby/bin/bundle exec puma -b tcp://127.0.0.1:8080 -e production
UMask=0077
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable zax
  # restart, not start: a re-run must pick up freshly pulled code
  systemctl restart zax
  # Wait for puma to boot, then check host authorization both ways.
  for _ in $(seq 1 30); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $HOST" http://127.0.0.1:8080/)" = 200 ] && break
    sleep 2
  done
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $HOST" http://127.0.0.1:8080/)" = 200 ]
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/)" = 403 ]
  # UMask above makes new files private; a seed created by an older unit
  # may still be 644 — fix it as the owner, never as root inside its tree
  su "$APP_USER" -c '[ ! -f ~/zax/shared/uploads/secret_seed.txt ] || chmod 600 ~/zax/shared/uploads/secret_seed.txt'
}

step_nginx() { # manual §8
  if grep -qs 'listen 443' "$NGINX_SITE"; then
    echo "site config already TLS-enabled by certbot — leaving it in place"
  else
    cat >"$NGINX_SITE" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $HOST;
    client_max_body_size 4m;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX
  fi
  rm -f /etc/nginx/sites-enabled/default
  ln -sfn "$NGINX_SITE" /etc/nginx/sites-enabled/zax

  # No version in the Server header or on nginx's own error pages. Ubuntu
  # ships «server_tokens build;» in nginx.conf: edit it in place, a second
  # copy in conf.d would be a duplicate-directive error.
  sed -i -E 's/^(\s*)#?\s*server_tokens\s.*/\1server_tokens off;/' /etc/nginx/nginx.conf
  local tokens=""
  grep -qE '^\s*server_tokens off;' /etc/nginx/nginx.conf || tokens="server_tokens off;"

  # Three response headers that cannot break the page, because none of them
  # restricts what it loads. add_header does not stack: one inside the site's
  # server or location blocks would silently discard this set, so the site
  # file stays free of it.
  cat >"$NGINX_HEADERS" <<HEADERS
# managed by install.sh — rewritten on every run
$tokens
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options DENY always;
add_header Referrer-Policy no-referrer always;
HEADERS

  # Requests that do not carry the relay's name get nothing: no page, no
  # certificate, so the bare address cannot be tied to the relay. The 443
  # half needs ssl_reject_handshake (nginx 1.19.4, Ubuntu 22.10 and later);
  # an older nginx gets the port-80 half only and says so in the log.
  local nginx_ver reject443=""
  nginx_ver=$(nginx -v 2>&1 | sed -E 's#.*nginx/([0-9.]+).*#\1#')
  if [ "$(printf '%s\n' 1.19.4 "$nginx_ver" | sort -V | head -n 1)" = 1.19.4 ]; then
    reject443='server { listen 443 ssl default_server; listen [::]:443 ssl default_server; server_name _; ssl_reject_handshake on; }'
  else
    echo "nginx $nginx_ver predates ssl_reject_handshake: the bare address still presents the certificate"
  fi
  cat >"$NGINX_DEFAULT" <<DEFAULT
# managed by install.sh — catch-all for connections without the relay's name
server { listen 80 default_server; listen [::]:80 default_server; server_name _; return 444; }
$reject443
DEFAULT

  nginx -t
  systemctl reload nginx
}

step_certbot() { # manual §9
  certbot --nginx -d "$HOST" -m "$EMAIL" --agree-tos --no-eff-email -n \
    --keep-until-expiring
}

step_hygiene() { # manual «Generic droplet hygiene»
  ufw limit OpenSSH
  ufw allow "Nginx Full"
  ufw --force enable

  # sshd: current cryptography only, and no Ubuntu build suffix in the
  # banner. The lists are subtractive: they remove what matches from
  # OpenSSH's defaults and error on nothing. A file sshd rejects is removed
  # again, which leaves sshd on Ubuntu's defaults, and the step fails and
  # says so. Existing sessions survive the restart.
  cat >"$SSHD_CONF" <<'SSHD'
# managed by install.sh — rewritten on every run
HostKey /etc/ssh/ssh_host_ed25519_key
KexAlgorithms -ecdh-sha2-nistp*,diffie-hellman-*
MACs -hmac-sha1*,umac-64*,umac-128@openssh.com,hmac-sha2-256,hmac-sha2-512
HostKeyAlgorithms -ecdsa-*,*rsa*,sk-ecdsa*
DebianBanner no
SSHD
  sshd -t || { rm -f "$SSHD_CONF"; return 1; }
  systemctl restart ssh

  # The relay's own log: puma writes its stdout into shared/log, which
  # nothing else rotates. A week is enough for debugging and keeps the
  # relay's traffic record short. copytruncate, because puma appends.
  cat >"$LOGROTATE_CONF" <<LOGROTATE
$APP_DIR/shared/log/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su $APP_USER $APP_USER
}
LOGROTATE
  local check
  check=$(logrotate -d "$LOGROTATE_CONF" 2>&1)
  case $check in *rror*) printf '%s\n' "$check"; return 1 ;; esac
}

step_verify() { # manual §10 — through the real DNS/proxy path
  local code="" token
  for _ in $(seq 1 10); do
    # "|| true": a refused connection must retry, not trip set -e
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$HOST/") || true
    [ "$code" = 200 ] && break
    sleep 5
  done
  [ "$code" = 200 ]
  token=$(head -c32 /dev/urandom | base64 | curl -s --max-time 15 --data @- "https://$HOST/start_session")
  printf '%s\n' "$token"
  # relay lines are \r\n-separated (protocol) — strip the CR before matching
  printf '%s\n' "$token" | head -n 1 | tr -d '\r' | grep -Eq '^[A-Za-z0-9+/]{43}=$'
}

run_step "Installing packages (takes a few minutes)"   "3. Install packages"             step_packages
run_step "Creating the $APP_USER user"                 "4. Create the app user"          step_user
run_step "Fetching $REPO ($BRANCH)"                    "6. Clone and install Zax"        step_clone
run_step "Installing Ruby with rv"                     "5. Install Ruby with rv"         step_ruby
run_step "Installing gems and dashboard (takes a few minutes)" "6. Clone and install Zax" step_bundle
run_step "Starting the zax service"                    "7. Run Zax as a systemd service" step_service
run_step "Configuring nginx"                           "8. Put nginx in front"           step_nginx
run_step "Getting a TLS certificate"                   "9. Get a TLS certificate"        step_certbot
run_step "Firewall, ssh cryptography, log rotation"      "Generic droplet hygiene"         step_hygiene
run_step "Verifying the relay end to end"              "10. Verify the relay"            step_verify

# ----------------------------------------------------------------- done --

say ""
say "Done — the relay is live:"
say "  https://$HOST/            dashboard"
say "  $APP_DIR/shared/log/  relay logs, rotated daily, a week kept"
say "  journalctl -u zax         service start and stop messages"
say "  $ENV_FILE              the relay's secrets, root-only"
say "  $LOG                      this install's transcript"
say ""
say "Re-run this script anytime to update the relay (pull, rebuild, restart)."
say "Once file uploads are in use, back up $APP_DIR/shared/uploads/secret_seed.txt."
say "ssh now offers only its ed25519 host key: a client that had cached the old"
say "ECDSA key asks you to confirm the new one once."
if TOP=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null) && [ "$TOP" != "$APP_DIR" ]; then
  say ""
  say "Note: the checkout at $TOP was only needed to run this script — the"
  say "relay lives in $APP_DIR; feel free to remove it."
fi
