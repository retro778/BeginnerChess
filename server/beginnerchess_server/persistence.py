"""SQLite storage: accounts, sessions, finished games, rating history.

One connection, protected by a lock; every public coroutine runs its work in
a worker thread (``asyncio.to_thread``) so the event loop never waits for the
disk. Every statement uses parameters (never string formatting with data).
Schema changes are numbered SQL files in ``server/migrations``.
"""

from __future__ import annotations

import asyncio
import hashlib
import sqlite3
import threading
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, TypeVar

T = TypeVar("T")

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "migrations"


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    return dt.isoformat(timespec="seconds")


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class Database:
    def __init__(self, path: str):
        self.path = path
        self.conn = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self.conn.row_factory = sqlite3.Row
        self.lock = threading.Lock()
        with self.lock:
            self.conn.execute("PRAGMA foreign_keys = ON")
            if path != ":memory:":
                self.conn.execute("PRAGMA journal_mode = WAL")
                self.conn.execute("PRAGMA synchronous = NORMAL")
            self.conn.execute("PRAGMA busy_timeout = 5000")
            self._migrate()

    # ------------------------------------------------------------------ infrastructure
    def _migrate(self) -> None:
        self.conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations "
                          "(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)")
        done = {row[0] for row in self.conn.execute("SELECT version FROM schema_migrations")}
        for file in sorted(MIGRATIONS_DIR.glob("[0-9][0-9][0-9][0-9]_*.sql")):
            version = int(file.name[:4])
            if version in done:
                continue
            script = file.read_text(encoding="utf-8")
            self.conn.execute("BEGIN")
            try:
                for statement in _split_sql(script):
                    self.conn.execute(statement)
                self.conn.execute("INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                                  (version, iso(utcnow())))
                self.conn.execute("COMMIT")
            except Exception:
                self.conn.execute("ROLLBACK")
                raise

    def schema_version(self) -> int:
        with self.lock:
            row = self.conn.execute("SELECT MAX(version) FROM schema_migrations").fetchone()
        return row[0] or 0

    async def run(self, fn: Callable[..., T], *args: Any) -> T:
        """Runs fn(conn, *args) in a worker thread inside one transaction."""
        def work() -> T:
            with self.lock:
                self.conn.execute("BEGIN IMMEDIATE")
                try:
                    result = fn(self.conn, *args)
                    self.conn.execute("COMMIT")
                    return result
                except Exception:
                    self.conn.execute("ROLLBACK")
                    raise
        return await asyncio.to_thread(work)

    def close(self) -> None:
        with self.lock:
            self.conn.close()

    def query_one(self, sql: str, *args: Any) -> Any:
        """One row of a query, taken under the lock (for tools and tests: the
        connection is shared with the worker threads)."""
        with self.lock:
            return self.conn.execute(sql, args).fetchone()

    def execute_now(self, sql: str, *args: Any) -> int:
        """One statement under the lock (for tools and tests); returns the row count."""
        with self.lock:
            return self.conn.execute(sql, args).rowcount

    def integrity_check(self) -> str:
        with self.lock:
            return self.conn.execute("PRAGMA integrity_check").fetchone()[0]

    def backup_to(self, target: str) -> None:
        """Consistent copy of the live database (SQLite online backup API)."""
        dest = sqlite3.connect(target)
        try:
            with self.lock:
                self.conn.backup(dest)
        finally:
            dest.close()

    # ------------------------------------------------------------------ users
    async def create_user(self, username: str, password_hash: str) -> dict[str, Any] | None:
        """New account, or None if the name is taken (case-insensitive)."""
        def fn(c: sqlite3.Connection):
            try:
                cur = c.execute("INSERT INTO users(username, password_hash, created_at) VALUES (?, ?, ?)",
                                (username, password_hash, iso(utcnow())))
            except sqlite3.IntegrityError:
                return None
            return dict(c.execute("SELECT * FROM users WHERE id = ?", (cur.lastrowid,)).fetchone())
        return await self.run(fn)

    async def user_by_name(self, username: str) -> dict[str, Any] | None:
        def fn(c):
            row = c.execute("SELECT * FROM users WHERE username = ? AND status != 'deleted'",
                            (username,)).fetchone()
            return dict(row) if row else None
        return await self.run(fn)

    async def user_by_id(self, user_id: int) -> dict[str, Any] | None:
        def fn(c):
            row = c.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
            return dict(row) if row else None
        return await self.run(fn)

    async def set_status(self, username: str, status: str) -> bool:
        def fn(c):
            return c.execute("UPDATE users SET status = ? WHERE username = ? AND status != 'deleted'",
                             (status, username)).rowcount > 0
        return await self.run(fn)

    async def delete_user(self, user_id: int) -> None:
        """Deletes the personal data of an account. Finished games stay (the
        opponent's history), but show "Deleted player" instead of the name."""
        def fn(c):
            c.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,))
            c.execute("DELETE FROM rating_history WHERE user_id = ?", (user_id,))
            c.execute("UPDATE games SET white_name = 'Deleted player', white_user_id = NULL "
                      "WHERE white_user_id = ?", (user_id,))
            c.execute("UPDATE games SET black_name = 'Deleted player', black_user_id = NULL "
                      "WHERE black_user_id = ?", (user_id,))
            # Games that now belong to nobody (the opponent was a guest or is deleted too).
            c.execute("DELETE FROM games WHERE white_user_id IS NULL AND black_user_id IS NULL")
            c.execute("UPDATE users SET username = ?, password_hash = '', status = 'deleted', "
                      "games = 0, wins = 0, losses = 0, draws = 0 WHERE id = ?",
                      (f"deleted-{user_id}", user_id))
        await self.run(fn)

    # ------------------------------------------------------------------ sessions
    async def create_session(self, user_id: int, token: str, days: int, keep: int = 10) -> None:
        """New session; only the newest ``keep`` sessions of a user are kept."""
        now = utcnow()
        def fn(c):
            c.execute("INSERT INTO sessions(user_id, token_hash, created_at, expires_at, last_used_at) "
                      "VALUES (?, ?, ?, ?, ?)",
                      (user_id, token_hash(token), iso(now), iso(now + timedelta(days=days)), iso(now)))
            c.execute("DELETE FROM sessions WHERE user_id = ? AND id NOT IN "
                      "(SELECT id FROM sessions WHERE user_id = ? ORDER BY id DESC LIMIT ?)",
                      (user_id, user_id, keep))
        await self.run(fn)

    async def session_user(self, token: str, days: int) -> dict[str, Any] | None:
        """The active account of a valid session token (and extends the session)."""
        now = utcnow()
        def fn(c):
            row = c.execute("SELECT s.id AS sid, s.expires_at, u.* FROM sessions s JOIN users u ON u.id = s.user_id "
                            "WHERE s.token_hash = ?", (token_hash(token),)).fetchone()
            if row is None:
                return None
            if row["expires_at"] < iso(now) or row["status"] != "active":
                c.execute("DELETE FROM sessions WHERE id = ?", (row["sid"],))
                return None
            c.execute("UPDATE sessions SET last_used_at = ?, expires_at = ? WHERE id = ?",
                      (iso(now), iso(now + timedelta(days=days)), row["sid"]))
            user = dict(row)
            user.pop("sid", None)
            user.pop("expires_at", None)
            return user
        return await self.run(fn)

    async def delete_session(self, token: str) -> None:
        await self.run(lambda c: c.execute("DELETE FROM sessions WHERE token_hash = ?", (token_hash(token),)))

    async def delete_sessions_of(self, user_id: int) -> int:
        return await self.run(lambda c: c.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,)).rowcount)

    async def purge_expired_sessions(self) -> int:
        return await self.run(lambda c: c.execute("DELETE FROM sessions WHERE expires_at < ?",
                                                  (iso(utcnow()),)).rowcount)

    # ------------------------------------------------------------------ games
    async def save_active_game(self, rec: dict[str, Any]) -> None:
        """Creates or updates the row of a running game (after every move)."""
        def fn(c):
            c.execute("INSERT INTO games(id, white_user_id, black_user_id, white_name, black_name, rated, "
                      "initial_ms, increment_ms, status, moves, final_fen, started_at, white_key, black_key, "
                      "white_ms, black_ms, draw_offer, seq, updated_at) "
                      "VALUES (?,?,?,?,?,?,?,?,'active',?,?,?,?,?,?,?,?,?,?) "
                      "ON CONFLICT(id) DO UPDATE SET moves = excluded.moves, final_fen = excluded.final_fen, "
                      "white_ms = excluded.white_ms, black_ms = excluded.black_ms, "
                      "draw_offer = excluded.draw_offer, seq = excluded.seq, updated_at = excluded.updated_at "
                      "WHERE games.status = 'active'",
                      (rec["id"], rec["white_user_id"], rec["black_user_id"], rec["white_name"], rec["black_name"],
                       int(rec["rated"]), rec["initial_ms"], rec["increment_ms"], rec["moves"], rec["final_fen"],
                       rec["started_at"], rec["white_key"], rec["black_key"], rec["white_ms"], rec["black_ms"],
                       rec["draw_offer"], rec["seq"], iso(utcnow())))
        await self.run(fn)

    async def delete_game(self, game_id: str) -> None:
        await self.run(lambda c: c.execute("DELETE FROM games WHERE id = ?", (game_id,)))

    async def active_games(self) -> list[dict[str, Any]]:
        return await self.run(lambda c: [dict(r) for r in c.execute(
            "SELECT * FROM games WHERE status = 'active' ORDER BY started_at").fetchall()])

    async def save_game(self, rec: dict[str, Any]) -> bool:
        """Stores a finished game and updates the players' statistics - exactly
        once: only the change from 'active' (or no row) to finished counts."""
        def fn(c):
            values = (rec["white_user_id"], rec["black_user_id"], rec["white_name"], rec["black_name"],
                      int(rec["rated"]), rec["initial_ms"], rec["increment_ms"], rec["status"], rec["result"],
                      rec["termination"], rec["moves"], rec["final_fen"], rec["pgn"], rec["started_at"],
                      rec["ended_at"])
            try:
                c.execute("INSERT INTO games(white_user_id, black_user_id, white_name, black_name, rated, "
                          "initial_ms, increment_ms, status, result, termination, moves, final_fen, pgn, "
                          "started_at, ended_at, id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                          values + (rec["id"],))
            except sqlite3.IntegrityError:
                updated = c.execute("UPDATE games SET white_user_id=?, black_user_id=?, white_name=?, black_name=?, "
                                    "rated=?, initial_ms=?, increment_ms=?, status=?, result=?, termination=?, "
                                    "moves=?, final_fen=?, pgn=?, started_at=?, ended_at=? "
                                    "WHERE id = ? AND status = 'active'", values + (rec["id"],)).rowcount
                if updated == 0:
                    return False                                 # already recorded
            if rec["status"] == "finished":
                for uid, colour in ((rec["white_user_id"], "w"), (rec["black_user_id"], "b")):
                    if uid is None:
                        continue
                    if rec["result"] == "1/2-1/2":
                        column = "draws"
                    elif (rec["result"] == "1-0") == (colour == "w"):
                        column = "wins"
                    else:
                        column = "losses"
                    # column is one of three fixed names, never data from a client
                    c.execute(f"UPDATE users SET games = games + 1, {column} = {column} + 1 WHERE id = ?", (uid,))
            return True
        return await self.run(fn)

    # ------------------------------------------------------------------ ratings
    async def rate_game(self, game_id: str, white_id: int, black_id: int, score_white: float,
                        calc) -> dict[str, tuple[int, int]] | None:
        """Applies an Elo result once per game (inside one transaction).
        calc(r_white, r_black, n_white, n_black, score_white) -> (new_white, new_black).
        Returns {"w": (before, after), "b": (before, after)} or None if already rated."""
        def fn(c):
            if c.execute("SELECT 1 FROM rating_history WHERE game_id = ?", (game_id,)).fetchone():
                return None
            w = c.execute("SELECT rating, rated_games FROM users WHERE id = ?", (white_id,)).fetchone()
            b = c.execute("SELECT rating, rated_games FROM users WHERE id = ?", (black_id,)).fetchone()
            if w is None or b is None:
                return None
            nw, nb = calc(w[0], b[0], w[1], b[1], score_white)
            now = iso(utcnow())
            for uid, before, after in ((white_id, w[0], nw), (black_id, b[0], nb)):
                c.execute("UPDATE users SET rating = ?, rated_games = rated_games + 1 WHERE id = ?", (after, uid))
                c.execute("INSERT INTO rating_history(user_id, game_id, rating_before, rating_after, created_at) "
                          "VALUES (?, ?, ?, ?, ?)", (uid, game_id, before, after, now))
            return {"w": (w[0], nw), "b": (b[0], nb)}
        return await self.run(fn)

    async def leaderboard(self, offset: int, limit: int) -> tuple[int, list[dict[str, Any]]]:
        def fn(c):
            total = c.execute("SELECT COUNT(*) FROM users WHERE status = 'active' AND rated_games > 0").fetchone()[0]
            rows = c.execute("SELECT username, rating, rated_games FROM users "
                             "WHERE status = 'active' AND rated_games > 0 "
                             "ORDER BY rating DESC, rated_games DESC, username LIMIT ? OFFSET ?",
                             (limit, offset)).fetchall()
            return total, [dict(r) for r in rows]
        return await self.run(fn)

    async def games_of(self, user_id: int, offset: int, limit: int) -> list[dict[str, Any]]:
        def fn(c):
            rows = c.execute("SELECT id, white_name, black_name, white_user_id, black_user_id, rated, initial_ms, "
                             "increment_ms, status, result, termination, ended_at FROM games "
                             "WHERE (white_user_id = ? OR black_user_id = ?) AND status != 'active' "
                             "ORDER BY ended_at DESC, id "
                             "LIMIT ? OFFSET ?", (user_id, user_id, limit, offset)).fetchall()
            return [dict(r) for r in rows]
        return await self.run(fn)

    async def game_record(self, game_id: str) -> dict[str, Any] | None:
        def fn(c):
            row = c.execute("SELECT * FROM games WHERE id = ? AND status != 'active'", (game_id,)).fetchone()
            return dict(row) if row else None              # running games are not records yet
        return await self.run(fn)

    async def counts(self) -> dict[str, int]:
        def fn(c):
            return {"users": c.execute("SELECT COUNT(*) FROM users WHERE status != 'deleted'").fetchone()[0],
                    "games": c.execute("SELECT COUNT(*) FROM games").fetchone()[0],
                    "sessions": c.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]}
        return await self.run(fn)


def _split_sql(script: str) -> list[str]:
    """Splits a migration file into statements. Comments ("--" to the end of the
    line) are removed first; migration files must not use "--" or ";" inside strings."""
    lines = [ln.split("--", 1)[0] for ln in script.splitlines()]
    return [s.strip() for s in "\n".join(lines).split(";") if s.strip()]
