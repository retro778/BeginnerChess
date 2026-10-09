"""Operator administration over a Unix socket (no network port, no web page).

The running server listens on ``admin_socket`` (set in the configuration; the
file permissions - 0660 by default - decide who may administer: normally the
service user and the operator via ``sudo``). The command-line tool
``python -m beginnerchess_server.admin`` sends one JSON request per
connection and prints the answer.

Commands: status, suspend, unsuspend, kick, set (registration / rated_games /
guests, until the next restart), backup, integrity.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sqlite3
import time
from typing import Any

from . import PROTOCOL_VERSION, __version__
from . import protocol as P

log = logging.getLogger("beginnerchess.admin")


class ErrorCounter(logging.Handler):
    """Counts ERROR (and worse) log records for the status report."""

    def __init__(self):
        super().__init__(level=logging.ERROR)
        self.count = 0
        self.last: float | None = None
        self.last_message = ""

    def emit(self, record: logging.LogRecord) -> None:
        self.count += 1
        self.last = time.time()
        self.last_message = record.getMessage()[:200]


def verify_backup(path: str) -> str:
    conn = sqlite3.connect(path)
    try:
        return conn.execute("PRAGMA integrity_check").fetchone()[0]
    finally:
        conn.close()


class Admin:
    def __init__(self, server):
        self.server = server
        self.errors = ErrorCounter()
        logging.getLogger().addHandler(self.errors)
        self._unix: asyncio.base_events.Server | None = None

    async def start(self, path: str, mode: str = "660") -> None:
        if os.path.exists(path):
            os.unlink(path)                         # stale socket from an earlier run
        old_umask = os.umask(0o077)                 # never world-accessible, not even briefly
        try:
            self._unix = await asyncio.start_unix_server(self._handle, path=path)
        finally:
            os.umask(old_umask)
        os.chmod(path, int(mode, 8))
        log.info("event=admin_socket path=%s", path)

    async def stop(self) -> None:
        if self._unix is not None:
            self._unix.close()
            await self._unix.wait_closed()
            self._unix = None
        logging.getLogger().removeHandler(self.errors)

    async def _handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            line = await asyncio.wait_for(reader.readline(), 10)
            request = json.loads(line or b"{}")
            answer = await self.execute(request)
        except Exception as err:                     # report, never crash the server
            answer = {"ok": False, "error": f"{type(err).__name__}: {err}"}
        writer.write(json.dumps(answer).encode() + b"\n")
        await writer.drain()
        writer.close()

    async def execute(self, req: dict[str, Any]) -> dict[str, Any]:
        cmd = req.get("cmd")
        srv = self.server
        if cmd == "status":
            counts = await srv.db.counts()
            online = list(srv.presence.online.values())
            return {"ok": True, "version": __version__, "protocol_version": PROTOCOL_VERSION,
                    "uptime_seconds": int(time.monotonic() - srv.started_at),
                    "connections": len(srv.registry),
                    "players_online": len(online),
                    "guests_online": sum(1 for p, _ in online if p.is_guest),
                    "active_games": sum(1 for g in srv.games.games.values() if g.status == "active"),
                    "matchmaking_queue": len(srv.lobby.queue),
                    "open_challenges": len(srv.lobby.challenges),
                    "database": {**counts, "schema_version": srv.db.schema_version()},
                    "features": srv.features(),
                    "errors_logged": self.errors.count,
                    "last_error_at": self.errors.last,
                    "last_error": self.errors.last_message}
        if cmd in ("suspend", "unsuspend", "kick"):
            name = str(req.get("user", ""))
            user = await srv.db.user_by_name(name)
            if user is None:
                return {"ok": False, "error": f"no such account: {name}"}
            if cmd == "unsuspend":
                await srv.db.set_status(user["username"], "active")
                log.info("event=admin_unsuspend user=%s", user["id"])
                return {"ok": True}
            if cmd == "suspend":
                await srv.db.set_status(user["username"], "suspended")
            ended = await srv.db.delete_sessions_of(user["id"])
            kicked = await self._disconnect(f"u-{user['id']}")
            log.info("event=admin_%s user=%s sessions=%d kicked=%s", cmd, user["id"], ended, kicked)
            return {"ok": True, "sessions_ended": ended, "connection_closed": kicked}
        if cmd == "set":
            feature, value = req.get("feature"), req.get("value")
            if not isinstance(value, bool):
                return {"ok": False, "error": "value must be true or false"}
            if feature == "registration":
                srv.config.registration_enabled = value
                srv.accounts.registration_enabled = value
            elif feature == "rated_games":
                srv.config.rated_games_enabled = value
                srv.lobby.rated_enabled = value
            elif feature == "guests":
                srv.config.guest_access_enabled = value
                srv.lobby.guests_enabled = value
            else:
                return {"ok": False, "error": "feature must be registration, rated_games or guests"}
            log.info("event=admin_set feature=%s value=%s", feature, value)
            return {"ok": True, "features": srv.features(),
                    "note": "until the next restart - change the configuration file to keep it"}
        if cmd == "backup":
            target = str(req.get("path", ""))
            if not target:
                return {"ok": False, "error": "path is missing"}
            await asyncio.to_thread(srv.db.backup_to, target)
            check = await asyncio.to_thread(verify_backup, target)
            log.info("event=admin_backup path=%s check=%s", target, check)
            return {"ok": check == "ok", "path": target, "integrity_check": check}
        if cmd == "integrity":
            return {"ok": True, "integrity_check": await asyncio.to_thread(srv.db.integrity_check)}
        return {"ok": False, "error": f"unknown command: {cmd}"}

    async def _disconnect(self, player_id: str) -> bool:
        entry = self.server.presence.online.get(player_id)
        if entry is None:
            return False
        player, client = entry
        await client.send({"type": "server_notice", "message": "Your session was ended by the server operator."})
        await client.ws.close(P.CLOSE_ADMIN, "ended by operator")
        return True
