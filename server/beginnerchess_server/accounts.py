"""Registered accounts: registration, login, sessions, profiles, match history.

* Passwords are hashed with Argon2id (argon2-cffi defaults) in a worker
  thread; they are never stored or logged in plain text.
* A login returns a session token (256 random bits). The server stores only
  its SHA-256 hash. The client may keep the token ("remember me") to log in
  again with ``resume`` without the password. Sessions expire after
  ``session_days`` without use; ``logout`` deletes them.
* Failed logins are throttled per account name and per address.
* Usernames: 3-16 letters, digits or ``_``; not starting with "guest";
  unique regardless of case.
* There is no e-mail address and therefore no password recovery.
"""

from __future__ import annotations

import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor
import re
import secrets
import time
from collections import defaultdict, deque
from typing import Any

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

from . import protocol as P
from .connections import Client
from .persistence import Database
from .players import Player, Presence

log = logging.getLogger("beginnerchess.accounts")

USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{3,16}$")
MIN_PASSWORD, MAX_PASSWORD = 8, 128
HISTORY_LIMIT = 50


class LoginThrottle:
    """At most ``per_name`` failures per account name and ``per_ip`` per address
    within ``window`` seconds."""

    def __init__(self, per_name: int = 5, per_ip: int = 20, window: float = 900.0, clock=time.monotonic):
        self.per_name, self.per_ip, self.window, self.clock = per_name, per_ip, window, clock
        self.failures: dict[str, deque[float]] = defaultdict(deque)

    def _count(self, key: str) -> int:
        q, now = self.failures[key], self.clock()
        while q and now - q[0] > self.window:
            q.popleft()
        if not q:
            del self.failures[key]
            return 0
        return len(q)

    def blocked(self, name: str, ip: str) -> bool:
        return self._count("n:" + name.lower()) >= self.per_name or self._count("i:" + ip) >= self.per_ip

    def failed(self, name: str, ip: str) -> None:
        now = self.clock()
        self.failures["n:" + name.lower()].append(now)
        self.failures["i:" + ip].append(now)

    def blocked_ip(self, ip: str) -> bool:
        return self._count("i:" + ip) >= self.per_ip

    def failed_ip(self, ip: str) -> None:
        self.failures["i:" + ip].append(self.clock())

    def succeeded(self, name: str) -> None:
        self.failures.pop("n:" + name.lower(), None)


def player_from_user(user: dict[str, Any]) -> Player:
    return Player(player_id=f"u-{user['id']}", name=user["username"], kind="account",
                  rating=user["rating"], provisional=user["rated_games"] < 20, account_id=user["id"])


def colour_result(result: str | None, colour: str) -> str:
    if result is None:
        return "aborted"
    if result == "1/2-1/2":
        return "draw"
    return "win" if (result == "1-0") == (colour == "w") else "loss"


class Accounts:
    def __init__(self, db: Database, presence: Presence, *, registration_enabled: bool = True,
                 session_days: int = 30, hasher: PasswordHasher | None = None,
                 throttle: LoginThrottle | None = None):
        self.db = db
        self.presence = presence
        self.registration_enabled = registration_enabled
        self.session_days = session_days
        self.hasher = hasher or PasswordHasher()        # Argon2id
        self.throttle = throttle or LoginThrottle()
        self.lobby = None                                # set by the server (lobby updates)
        # Argon2id needs 64 MiB per hash: at most two at a time bounds the memory.
        self.hash_pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="argon2")

    def register_routes(self, server) -> None:
        cfg = server.config
        server.route("register", self.handle_register, limit=(cfg.registrations_per_hour, 3600.0), scope="ip")
        server.route("login", self.handle_login)
        server.route("resume", self.handle_resume)
        server.route("logout", self.handle_logout, auth="player")
        server.route("delete_account", self.handle_delete, auth="player", limit=(5, 3600.0), scope="ip")
        server.route("profile", self.handle_profile, auth="player")
        server.route("history", self.handle_history, auth="player")
        server.route("game_record", self.handle_game_record, auth="player")
        server.route("leaderboard", self.handle_leaderboard, auth="player")
        self.server = server

    # ------------------------------------------------------------------ helpers
    @staticmethod
    def check_username(name: str | None) -> str:
        if not isinstance(name, str) or not USERNAME_RE.match(name):
            raise P.ProtocolError(P.BAD_MESSAGE, "A user name has 3-16 letters, digits or '_'.")
        if name.lower().startswith("guest"):
            raise P.ProtocolError(P.BAD_MESSAGE, "User names may not start with 'Guest'.")
        return name

    @staticmethod
    def check_password(pw: Any) -> str:
        if not isinstance(pw, str) or not (MIN_PASSWORD <= len(pw) <= MAX_PASSWORD):
            raise P.ProtocolError(P.BAD_MESSAGE, f"A password has {MIN_PASSWORD}-{MAX_PASSWORD} characters.")
        return pw

    async def _hash(self, pw: str) -> str:
        return await asyncio.get_running_loop().run_in_executor(self.hash_pool, self.hasher.hash, pw)

    async def _verify(self, stored: str, pw: str) -> bool:
        def check() -> bool:
            try:
                return self.hasher.verify(stored, pw)
            except (VerifyMismatchError, VerificationError, InvalidHashError):
                return False
        return await asyncio.get_running_loop().run_in_executor(self.hash_pool, check)

    async def _log_in(self, client: Client, msg: dict[str, Any], user: dict[str, Any],
                      token: str | None) -> None:
        """Binds the account to the connection and answers ``logged_in``."""
        if client.identity is not None:
            raise P.ProtocolError(P.CONFLICT, "You are already logged in.")
        player = player_from_user(user)
        if token is not None:
            player.session = token
        old = self.presence.attach(player, client)
        if old is not None:
            # The same account on another connection: only one at a time.
            await old.send({"type": "session_replaced",
                            "message": "You logged in from another place."})
            old.identity = None
            await old.ws.close(P.CLOSE_SESSION_REPLACED, "session replaced")
        reply: dict[str, Any] = {"player": player.public(),
                                 "stats": {k: user[k] for k in ("games", "wins", "losses", "draws")}}
        if token is not None:
            reply["session_token"] = token
        await client.send(P.reply(msg, "logged_in", **reply))
        if self.lobby is not None:
            self.lobby.changed()
        await self.server.games.player_connected(player)     # continue a running game

    async def _new_session(self, user_id: int) -> str:
        token = secrets.token_urlsafe(32)
        await self.db.create_session(user_id, token, self.session_days, self.server.config.sessions_per_user)
        return token

    # ------------------------------------------------------------------ requests
    async def handle_register(self, client: Client, msg: dict[str, Any]) -> None:
        if not self.registration_enabled:
            raise P.ProtocolError(P.UNAVAILABLE, "Registration is switched off on this server.")
        if client.identity is not None:
            raise P.ProtocolError(P.CONFLICT, "Please log out first.")
        name = self.check_username(msg.get("username"))
        pw = self.check_password(msg.get("password"))
        if pw.lower() == name.lower():
            raise P.ProtocolError(P.BAD_MESSAGE, "The password must be different from the user name.")
        user = await self.db.create_user(name, await self._hash(pw))
        if user is None:
            raise P.ProtocolError(P.CONFLICT, "This user name is already taken.")
        log.info("event=registered user=%s", user["id"])
        await self._log_in(client, msg, user, await self._new_session(user["id"]))

    async def handle_login(self, client: Client, msg: dict[str, Any]) -> None:
        if client.identity is not None:
            raise P.ProtocolError(P.CONFLICT, "Please log out first.")
        name = P.get_str(msg, "username", max_len=32, min_len=1)
        pw = P.get_str(msg, "password", max_len=MAX_PASSWORD, min_len=1)
        assert name is not None and pw is not None
        if self.throttle.blocked(name, client.ip):
            raise P.ProtocolError(P.RATE_LIMITED, "Too many failed logins. Please wait a few minutes.")
        user = await self.db.user_by_name(name)
        ok = user is not None and user["password_hash"] != "" and await self._verify(user["password_hash"], pw)
        if user is None:
            await self._verify(DUMMY_HASH, pw)          # same time with and without an account
        if not ok:
            self.throttle.failed(name, client.ip)
            log.info("event=login_failed conn=%s", client.conn_id)
            raise P.ProtocolError(P.FORBIDDEN, "Wrong user name or password.")
        if user["status"] != "active":
            raise P.ProtocolError(P.FORBIDDEN, "This account is suspended.")
        self.throttle.succeeded(name)
        if self.hasher.check_needs_rehash(user["password_hash"]):
            new_hash = await self._hash(pw)
            await self.db.run(lambda c: c.execute("UPDATE users SET password_hash = ? WHERE id = ?",
                                                  (new_hash, user["id"])))
        log.info("event=login user=%s conn=%s", user["id"], client.conn_id)
        await self._log_in(client, msg, user, await self._new_session(user["id"]))

    async def handle_resume(self, client: Client, msg: dict[str, Any]) -> None:
        if client.identity is not None:
            raise P.ProtocolError(P.CONFLICT, "You are already logged in.")
        token = P.get_str(msg, "session_token", max_len=128, min_len=20)
        assert token is not None
        if self.throttle.blocked_ip(client.ip):
            raise P.ProtocolError(P.RATE_LIMITED, "Too many attempts. Please wait a few minutes.")
        guest = self.server.lobby.resume_guest(token)
        if guest is not None:                                # a guest coming back to a running game
            old = self.presence.attach(guest, client)
            if old is not None:
                old.identity = None
                await old.ws.close(P.CLOSE_SESSION_REPLACED, "session replaced")
            log.info("event=guest_resume conn=%s", client.conn_id)
            await client.send(P.reply(msg, "logged_in", player=guest.public(), session_token=token))
            self.server.lobby.changed()
            await self.server.games.player_connected(guest)
            return
        user = await self.db.session_user(token, self.session_days)
        if user is None:
            self.throttle.failed_ip(client.ip)
            raise P.ProtocolError(P.NOT_AUTHENTICATED, "Your login has expired. Please log in again.")
        log.info("event=resume user=%s conn=%s", user["id"], client.conn_id)
        await self._log_in(client, msg, user, token)

    async def handle_logout(self, client: Client, msg: dict[str, Any]) -> None:
        player: Player = client.identity
        if self.server.games.is_playing(player):
            raise P.ProtocolError(P.CONFLICT, "Finish your game first.")
        if player.session:
            await self.db.delete_session(player.session)
        self.presence.detach(client)
        client.identity = None
        await self.server.lobby.player_left(player)      # leaves the queue, cancels challenges
        await client.send(P.reply(msg, "logged_out"))

    async def handle_delete(self, client: Client, msg: dict[str, Any]) -> None:
        player: Player = client.identity
        if player.account_id is None:
            raise P.ProtocolError(P.FORBIDDEN, "Guests have no account to delete.")
        if self.server.games.is_playing(player):
            raise P.ProtocolError(P.CONFLICT, "Finish your game first.")
        pw = P.get_str(msg, "password", max_len=MAX_PASSWORD, min_len=1)
        user = await self.db.user_by_id(player.account_id)
        if user is None or not await self._verify(user["password_hash"], pw or ""):
            raise P.ProtocolError(P.FORBIDDEN, "Wrong password.")
        await self.db.delete_user(player.account_id)
        log.info("event=account_deleted user=%s", player.account_id)
        self.presence.detach(client)
        client.identity = None
        await self.server.lobby.player_left(player)
        await client.send(P.reply(msg, "account_deleted"))

    async def handle_profile(self, client: Client, msg: dict[str, Any]) -> None:
        name = P.get_str(msg, "username", max_len=32, min_len=1, optional=True)
        me: Player = client.identity
        if name is None:
            if me.account_id is None:
                raise P.ProtocolError(P.FORBIDDEN, "Guests have no online profile. Register to keep your games.")
            user = await self.db.user_by_id(me.account_id)
        else:
            user = await self.db.user_by_name(name)
        if user is None or user["status"] == "deleted":
            raise P.ProtocolError(P.NOT_FOUND, "No such player.")
        games = await self.db.games_of(user["id"], 0, 10)
        await client.send(P.reply(msg, "profile", profile={
            "name": user["username"], "rating": user["rating"], "provisional": user["rated_games"] < 20,
            "rated_games": user["rated_games"], "games": user["games"], "wins": user["wins"],
            "losses": user["losses"], "draws": user["draws"], "member_since": user["created_at"][:7],
            "recent_games": [self._summary(g, user["id"]) for g in games]}))

    async def handle_history(self, client: Client, msg: dict[str, Any]) -> None:
        me: Player = client.identity
        if me.account_id is None:
            raise P.ProtocolError(P.FORBIDDEN, "Guest games are not kept. Register to keep your games.")
        offset = P.get_int(msg, "offset", lo=0, hi=1_000_000, optional=True, default=0)
        limit = P.get_int(msg, "limit", lo=1, hi=HISTORY_LIMIT, optional=True, default=20)
        games = await self.db.games_of(me.account_id, offset or 0, limit or 20)
        await client.send(P.reply(msg, "history", offset=offset,
                                  games=[self._summary(g, me.account_id) for g in games]))

    async def handle_game_record(self, client: Client, msg: dict[str, Any]) -> None:
        gid = P.get_str(msg, "game_id", max_len=32, min_len=1)
        rec = await self.db.game_record(gid or "")
        if rec is None:
            raise P.ProtocolError(P.NOT_FOUND, "No such game.")
        await client.send(P.reply(msg, "game_record", game={
            "game_id": rec["id"], "white": rec["white_name"], "black": rec["black_name"],
            "rated": bool(rec["rated"]), "result": rec["result"], "termination": rec["termination"],
            "status": rec["status"], "moves": rec["moves"].split(), "final_fen": rec["final_fen"],
            "pgn": rec["pgn"], "started_at": rec["started_at"], "ended_at": rec["ended_at"],
            "time_control": {"initial_seconds": rec["initial_ms"] // 1000,
                             "increment_seconds": rec["increment_ms"] // 1000}}))

    async def handle_leaderboard(self, client: Client, msg: dict[str, Any]) -> None:
        offset = P.get_int(msg, "offset", lo=0, hi=1_000_000, optional=True, default=0) or 0
        limit = P.get_int(msg, "limit", lo=1, hi=50, optional=True, default=20) or 20
        total, rows = await self.db.leaderboard(offset, limit)
        await client.send(P.reply(msg, "leaderboard", offset=offset, total=total, players=[
            {"rank": offset + i + 1, "name": r["username"], "rating": r["rating"],
             "games": r["rated_games"], "provisional": r["rated_games"] < 20} for i, r in enumerate(rows)]))

    @staticmethod
    def _summary(g: dict[str, Any], user_id: int) -> dict[str, Any]:
        colour = "w" if g["white_user_id"] == user_id else "b"
        return {"game_id": g["id"], "white": g["white_name"], "black": g["black_name"],
                "color": colour, "opponent": g["black_name"] if colour == "w" else g["white_name"],
                "outcome": colour_result(g["result"], colour), "result": g["result"],
                "termination": g["termination"], "rated": bool(g["rated"]),
                "time_control": {"initial_seconds": g["initial_ms"] // 1000,
                                 "increment_seconds": g["increment_ms"] // 1000},
                "date": (g["ended_at"] or "")[:10]}

    # ------------------------------------------------------------------ game end
    async def on_game_end(self, game) -> None:
        """Stores the finished game if at least one player has an account (for
        the match histories). Games between two guests are not stored."""
        if not game.has_account():
            return
        await self.db.save_game({
            "id": game.game_id,
            "white_user_id": game.white.account_id, "black_user_id": game.black.account_id,
            "white_name": game.white.name, "black_name": game.black.name, "rated": game.rated,
            "initial_ms": game.tc.initial_ms, "increment_ms": game.tc.increment_ms,
            "status": game.status, "result": game.result, "termination": game.termination,
            "moves": " ".join(game.ucis), "final_fen": game.board.fen(), "pgn": game.pgn(),
            "started_at": game.started_at, "ended_at": game.ended_at})


# A valid Argon2id hash of a random secret: verifying against it costs the same
# time as a real check, so response times do not reveal whether a name exists.
DUMMY_HASH = PasswordHasher().hash(secrets.token_hex(16))
