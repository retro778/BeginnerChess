#!/bin/sh
# Removes the BeginnerChess server again (run as root). Keeps the database and
# backups unless --purge is given. Does not touch other services or firewall rules.
#   sudo sh uninstall.sh [--purge] [--remove-packages]
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }
systemctl disable --now beginnerchess-server.service beginnerchess-backup.timer 2>/dev/null || true
rm -f /etc/systemd/system/beginnerchess-server.service /etc/systemd/system/beginnerchess-backup.service \
      /etc/systemd/system/beginnerchess-backup.timer
systemctl daemon-reload
rm -f /etc/nginx/sites-enabled/beginnerchess /etc/nginx/sites-available/beginnerchess
if command -v nginx >/dev/null 2>&1; then nginx -t && systemctl reload nginx || true; fi
if command -v ufw >/dev/null 2>&1; then
    ufw delete allow 80/tcp || true
    ufw delete allow 443/tcp || true
fi
rm -rf /opt/beginnerchess /etc/beginnerchess
for arg in "$@"; do
    case "$arg" in
    --purge) rm -rf /var/lib/beginnerchess /var/backups/beginnerchess; deluser --system beginnerchess || true ;;
    --remove-packages) apt-get remove -y nginx certbot ;;
    esac
done
echo "BeginnerChess server removed."
