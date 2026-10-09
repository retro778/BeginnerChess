#!/bin/sh
# BeginnerChess database backup (run by beginnerchess-backup.timer, or by hand).
# Uses SQLite's online backup API through the running server (safe while games
# are played), verifies the copy, and keeps the newest $KEEP backups.
set -eu
BACKUP_DIR="${BACKUP_DIR:-/var/backups/beginnerchess}"
SOCKET="${SOCKET:-/run/beginnerchess/admin.sock}"
DATABASE="${DATABASE:-/var/lib/beginnerchess/beginnerchess.db}"
KEEP="${KEEP:-14}"
PYTHON="${PYTHON:-/opt/beginnerchess/server/.venv/bin/python}"
cd /opt/beginnerchess/server

mkdir -p "$BACKUP_DIR"
target="$BACKUP_DIR/beginnerchess-$(date -u +%Y%m%d-%H%M%S).db"
if [ -S "$SOCKET" ]; then
    "$PYTHON" -m beginnerchess_server.admin --socket "$SOCKET" backup "$target"
else
    # Server not running: copy the file with the same API (read-only).
    "$PYTHON" -m beginnerchess_server.admin --database "$DATABASE" backup "$target"
fi
chmod 600 "$target"
# Keep the newest $KEEP backups.
ls -1t "$BACKUP_DIR"/beginnerchess-*.db 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
    rm -f -- "$old"
done
echo "backup ok: $target"
