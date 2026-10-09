"""Command-line administration of a BeginnerChess server.

    python -m beginnerchess_server.admin --socket /run/beginnerchess/admin.sock status
    ... suspend NAME | unsuspend NAME | kick NAME
    ... set registration|rated_games|guests on|off
    ... backup /var/backups/beginnerchess/bc-2026-10-09.db
    ... integrity

Offline backup (server not running, or as a second safety net):

    python -m beginnerchess_server.admin --database /var/lib/beginnerchess/beginnerchess.db \\
        backup /var/backups/beginnerchess/copy.db

Both backups use SQLite's online backup API (safe while the server writes)
and verify the copy with PRAGMA integrity_check.
"""

from __future__ import annotations

import argparse
import json
import socket
import sqlite3
import sys


def send(path: str, request: dict) -> dict:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(30)
        s.connect(path)
        s.sendall(json.dumps(request).encode() + b"\n")
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
    return json.loads(data or b"{}")


def offline_backup(database: str, target: str) -> dict:
    src = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    dst = sqlite3.connect(target)
    try:
        src.backup(dst)
    finally:
        src.close()
    check = dst.execute("PRAGMA integrity_check").fetchone()[0]
    dst.close()
    return {"ok": check == "ok", "path": target, "integrity_check": check}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="beginnerchess-admin", description="BeginnerChess server administration")
    ap.add_argument("--socket", default="/run/beginnerchess/admin.sock", help="admin socket of the running server")
    ap.add_argument("--database", help="offline mode: database file (only 'backup' and 'integrity')")
    ap.add_argument("command", choices=["status", "suspend", "unsuspend", "kick", "set", "backup", "integrity"])
    ap.add_argument("args", nargs="*")
    a = ap.parse_args(argv)

    if a.command in ("suspend", "unsuspend", "kick"):
        if len(a.args) != 1:
            ap.error(f"{a.command} needs a user name")
        request = {"cmd": a.command, "user": a.args[0]}
    elif a.command == "set":
        if len(a.args) != 2 or a.args[1] not in ("on", "off"):
            ap.error("usage: set registration|rated_games|guests on|off")
        request = {"cmd": "set", "feature": a.args[0], "value": a.args[1] == "on"}
    elif a.command == "backup":
        if len(a.args) != 1:
            ap.error("backup needs a target file")
        request = {"cmd": "backup", "path": a.args[0]}
    else:
        request = {"cmd": a.command}

    try:
        if a.database:
            if a.command == "backup":
                answer = offline_backup(a.database, a.args[0])
            elif a.command == "integrity":
                conn = sqlite3.connect(f"file:{a.database}?mode=ro", uri=True)
                answer = {"ok": True, "integrity_check": conn.execute("PRAGMA integrity_check").fetchone()[0]}
                conn.close()
            else:
                ap.error("--database works only with backup and integrity")
        else:
            answer = send(a.socket, request)
    except (OSError, sqlite3.Error) as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    print(json.dumps(answer, indent=2))
    return 0 if answer.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
