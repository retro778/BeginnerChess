#!/bin/sh
# BeginnerChess server installation on Debian/Ubuntu (run as root).
#
#   sudo sh install.sh /path/to/server-folder
#
# Safe to run again (each step checks what is already there). What it does:
#   1. snapshot of things that must NOT change (existing firewall rules, and the
#      services and folders named in PROTECT_SERVICES / PROTECT_PATHS)
#   2. packages: nginx, certbot, python3-venv
#   3. system user "beginnerchess", program in /opt/beginnerchess/server
#      (owned by root, read-only for the service), Python venv, config
#   4. systemd: beginnerchess-server.service, beginnerchess-backup.timer
#   5. Nginx (HTTP stage), firewall: ADDS 80/tcp and 443/tcp (nothing removed)
#   6. Let's Encrypt certificate for $DOMAIN (webroot), Nginx TLS stage
#   7. checks: local and public health, snapshot compared again
# It never starts, stops, enables, disables or edits other services, and adds
# firewall rules without removing or changing existing ones.
#
# Optional environment variables:
#   DOMAIN            the server's domain name (default freedomnet.tech)
#   CERT_EMAIL        e-mail for Let's Encrypt expiry notices (default: none)
#   PROTECT_SERVICES  systemd units whose enabled/active state must not change,
#                     e.g. "postfix mysite"   (checked before and after)
#   PROTECT_PATHS     files or folders whose contents must not change, e.g.
#                     "/var/www/mysite /etc/mysite"   (checksummed before and after)
set -eu
DOMAIN="${DOMAIN:-freedomnet.tech}"
CERT_EMAIL="${CERT_EMAIL:-}"            # optional: Let's Encrypt expiry notices
SRC="${1:?usage: install.sh SERVER_FOLDER}"
PROTECT_SERVICES="${PROTECT_SERVICES:-}"
PROTECT_PATHS="${PROTECT_PATHS:-}"
APP=/opt/beginnerchess/server
SNAP=/root/beginnerchess-install-snapshot

say() { printf '\n== %s\n' "$*"; }
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }
[ -f "$SRC/beginnerchess_server/__init__.py" ] || { echo "$SRC is not the server folder"; exit 1; }

snapshot() {
    for unit in $PROTECT_SERVICES; do
        echo "$unit enabled: $(systemctl is-enabled "$unit" 2>&1 || true)"
        echo "$unit active:  $(systemctl is-active "$unit" 2>&1 || true)"
    done
    for path in $PROTECT_PATHS; do
        if [ -e "$path" ]; then
            echo "$path: $(find "$path" -type f -print0 | sort -z | xargs -0 -r sha256sum | sha256sum)"
        else
            echo "$path: (missing)"
        fi
    done
    # Existing firewall rules (the rules added below carry a "BeginnerChess" comment).
    if command -v ufw >/dev/null 2>&1; then
        ufw status | grep -v 'BeginnerChess' || true
    fi
}

say "1. Snapshot of what must stay unchanged"
snapshot > "$SNAP.before"
cat "$SNAP.before"

say "2. Packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends nginx certbot python3-venv ca-certificates curl

say "3. User, program, virtual environment, configuration"
if ! id beginnerchess >/dev/null 2>&1; then
    adduser --system --group --home /var/lib/beginnerchess --no-create-home --shell /usr/sbin/nologin beginnerchess
fi
install -d -o root -g beginnerchess -m 0750 /opt/beginnerchess "$APP"
install -d -o beginnerchess -g beginnerchess -m 0750 /var/backups/beginnerchess
install -d -o root -g beginnerchess -m 0750 /etc/beginnerchess
# Program files: copy everything except the development venv and caches.
tar -C "$SRC" --exclude=.venv --exclude=__pycache__ --exclude=.pytest_cache --exclude='*.db' \
    --exclude='*.db-wal' --exclude='*.db-shm' -cf - . | tar -C "$APP" -xf -
chown -R root:beginnerchess "$APP"
chmod -R u=rwX,g=rX,o= "$APP"
chmod 0750 "$APP/deployment/scripts/backup.sh"
if [ ! -x "$APP/.venv/bin/python" ]; then
    python3 -m venv "$APP/.venv"
fi
"$APP/.venv/bin/pip" install -q --upgrade pip
"$APP/.venv/bin/pip" install -q -r "$APP/requirements.txt"
chown -R root:beginnerchess "$APP/.venv"
chmod -R g+rX,o= "$APP/.venv"
if [ ! -f /etc/beginnerchess/server.toml ]; then
    install -o root -g beginnerchess -m 0640 "$APP/deployment/server.toml" /etc/beginnerchess/server.toml
fi

say "4. systemd units"
install -m 0644 "$APP/deployment/systemd/beginnerchess-server.service" /etc/systemd/system/
install -m 0644 "$APP/deployment/systemd/beginnerchess-backup.service" /etc/systemd/system/
install -m 0644 "$APP/deployment/systemd/beginnerchess-backup.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable beginnerchess-server.service beginnerchess-backup.timer
systemctl restart beginnerchess-server.service
systemctl start beginnerchess-backup.timer
sleep 2
systemctl --no-pager --lines=5 status beginnerchess-server.service || true
curl -fsS http://127.0.0.1:8765/chess/health && echo

say "5. Nginx (HTTP stage) and firewall"
install -d -m 0755 /var/www/certbot
# A fresh nginx package enables its "default" site; it is replaced by ours.
if [ -L /etc/nginx/sites-enabled/default ] && [ "$(readlink -f /etc/nginx/sites-enabled/default)" = /etc/nginx/sites-available/default ]; then
    rm /etc/nginx/sites-enabled/default
fi
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    install -m 0644 "$APP/deployment/nginx/beginnerchess-http.conf" /etc/nginx/sites-available/beginnerchess
fi
ln -sf /etc/nginx/sites-available/beginnerchess /etc/nginx/sites-enabled/beginnerchess
nginx -t
systemctl enable nginx
systemctl reload nginx || systemctl restart nginx
if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp comment 'BeginnerChess: HTTP (certificates, redirect)'
    ufw allow 443/tcp comment 'BeginnerChess: HTTPS / WSS'
    ufw status
fi

say "6. Certificate and TLS"
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    if [ -n "$CERT_EMAIL" ]; then EMAIL_ARG="--email $CERT_EMAIL"; else EMAIL_ARG="--register-unsafely-without-email"; fi
    # shellcheck disable=SC2086
    certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" --agree-tos --non-interactive $EMAIL_ARG
fi
install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
printf '#!/bin/sh\nsystemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
install -m 0644 "$APP/deployment/nginx/beginnerchess.conf" /etc/nginx/sites-available/beginnerchess
nginx -t
systemctl reload nginx
systemctl list-timers certbot.timer --no-pager || true

say "7. Checks"
curl -fsS "https://$DOMAIN/chess/health" && echo
snapshot > "$SNAP.after"
if diff -u "$SNAP.before" "$SNAP.after"; then
    echo "OK: the existing firewall rules and the protected services/paths are unchanged."
else
    echo "WARNING: something in the snapshot changed (see above)."
    exit 1
fi
echo
echo "Done. Public endpoint: wss://$DOMAIN/chess/ws"
