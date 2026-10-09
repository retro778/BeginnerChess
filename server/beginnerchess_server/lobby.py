"""The online area: guest login, lobby list, quick match, direct challenges.

Guests choose a nickname (3-16 letters, digits or ``_``). It is shown as
``Guest_<nickname>``; account names can never start with "Guest", so a guest
can never look like a registered player. Two players online cannot have the
same name, and the name of a player in a running game stays reserved while
they are disconnected. Guests get a session token that is kept in memory only
and allows them to come back to a running game after a connection loss.

Quick match: players ask for a time control, casual or rated. Casual players
with the same time control are paired at once. Rated players (accounts only)
are paired if their ratings are close enough: the accepted difference starts
at 200 points and grows by 50 points every 5 seconds of waiting (up to 1000),
so nobody waits forever. Colours are random.

Direct challenges: one player challenges another (time control, casual or
rated). The server keeps the state; challenges expire after 60 seconds and are
cancelled when either player starts a game or leaves. At most 3 open
challenges per player, one per opponent.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import random
import re
import secrets
import time
from dataclasses import dataclass, field
from typing import Any

from . import protocol as P
from .connections import Client
from .games import GameManager, TimeControl
from .players import Player, Presence, new_guest_id

log = logging.getLogger("beginnerchess.lobby")

NICK_RE = re.compile(r"^[A-Za-z0-9_]{3,16}$")
LOBBY_LIMIT = 100              # players listed at most
LOBBY_THROTTLE = 0.5           # seconds: lobby updates are combined
CHALLENGE_SECONDS = 60
MAX_OUTGOING_CHALLENGES = 3
MAX_INCOMING_CHALLENGES = 10
RATED_RANGE_START = 200
RATED_RANGE_STEP = 50          # per RATED_RANGE_EVERY seconds of waiting
RATED_RANGE_EVERY = 5.0
RATED_RANGE_MAX = 1000


@dataclass
class QueueEntry:
    player: Player
    tc: TimeControl
    rated: bool
    since: float


@dataclass
class Challenge:
    challenge_id: str
    sender: Player
    receiver: Player
    tc: TimeControl
    rated: bool
    timer: asyncio.TimerHandle | None = field(default=None, repr=False)

    def public(self) -> dict[str, Any]:
        return {"challenge_id": self.challenge_id, "from": self.sender.public(), "to": self.receiver.public(),
                "time_control": self.tc.to_json(), "rated": self.rated, "expires_seconds": CHALLENGE_SECONDS}


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class Lobby:
    def __init__(self, presence: Presence, games: GameManager, *, guests_enabled: bool = True,
                 rated_enabled: bool = True, rng: random.Random | None = None,
                 clock=time.monotonic):
        self.presence = presence
        self.games = games
        self.guests_enabled = guests_enabled
        self.rated_enabled = rated_enabled
        self.queue: list[QueueEntry] = []
        self.rng = rng or random.Random()
        self.now = clock
        self.subscribers: dict[str, Client] = {}          # conn_id -> client watching the lobby
        self.challenges: dict[str, Challenge] = {}
        self.guest_sessions: dict[str, Player] = {}       # token hash -> guest (memory only)
        self._update_pending = False
        self._matcher: asyncio.Task | None = None
        games.on_game_end.append(self._game_ended)

    def register_routes(self, server) -> None:
        server.route("login_guest", self.handle_login_guest)
        cfg = server.config
        server.route("matchmaking_join", self.handle_join, auth="player",
                     limit=(cfg.matchmaking_per_minute, 60.0), scope="player")
        server.route("matchmaking_cancel", self.handle_cancel, auth="player")
        server.route("lobby_subscribe", self.handle_subscribe, auth="player")
        server.route("lobby_unsubscribe", self.handle_unsubscribe, auth="player")
        server.route("challenge", self.handle_challenge, auth="player",
                     limit=(cfg.challenges_per_minute, 60.0), scope="player")
        server.route("challenge_accept", self.handle_challenge_accept, auth="player")
        server.route("challenge_decline", self.handle_challenge_decline, auth="player")
        server.route("challenge_cancel", self.handle_challenge_cancel, auth="player")
        server.on_disconnect.append(self.on_disconnect)

    def start(self) -> None:
        """Starts the background matcher for rated games (ranges grow while waiting)."""
        if self._matcher is None:
            self._matcher = asyncio.get_running_loop().create_task(self._match_loop())

    def stop(self) -> None:
        if self._matcher is not None:
            self._matcher.cancel()
            self._matcher = None
        for ch in self.challenges.values():
            if ch.timer is not None:
                ch.timer.cancel()

    # ------------------------------------------------------------------ lobby list
    def status_of(self, player: Player) -> str:
        if self.games.is_playing(player):
            return "playing"
        if any(e.player.player_id == player.player_id for e in self.queue):
            return "waiting"
        return "available"

    def lobby_message(self) -> dict[str, Any]:
        order = {"available": 0, "waiting": 1, "playing": 2}
        entries = [{**p.public(), "status": self.status_of(p)} for p, _ in self.presence.online.values()]
        entries.sort(key=lambda e: (order[e["status"]], e["name"].lower()))
        return {"type": "lobby", "players": entries[:LOBBY_LIMIT], "total": len(entries)}

    def changed(self) -> None:
        """Something in the lobby changed: send one combined update soon."""
        if self._update_pending or not self.subscribers:
            return
        self._update_pending = True
        asyncio.get_running_loop().call_later(LOBBY_THROTTLE, lambda: asyncio.ensure_future(self._send_update()))

    async def _send_update(self) -> None:
        self._update_pending = False
        msg = self.lobby_message()
        for client in list(self.subscribers.values()):
            await client.send(msg)

    async def _game_ended(self, game) -> None:
        # Guest sessions only exist to come back to a running game.
        for key, p in list(self.guest_sessions.items()):
            if p.player_id in (game.white.player_id, game.black.player_id) and not self.presence.is_online(p):
                del self.guest_sessions[key]
        self.changed()

    async def handle_subscribe(self, client: Client, msg: dict[str, Any]) -> None:
        self.subscribers[client.conn_id] = client
        listing = self.lobby_message()
        await client.send(P.reply(msg, listing.pop("type"), **listing))

    async def handle_unsubscribe(self, client: Client, msg: dict[str, Any]) -> None:
        self.subscribers.pop(client.conn_id, None)
        await client.send(P.reply(msg, "ok"))

    # ------------------------------------------------------------------ names and guests
    def name_in_use(self, name: str) -> bool:
        lower = name.lower()
        if any(p.name.lower() == lower for p, _ in self.presence.online.values()):
            return True
        # Reserved for a disconnected player of a running game.
        for game in self.games.games.values():
            if game.status == "active" and lower in (game.white.name.lower(), game.black.name.lower()):
                return True
        return False

    def resume_guest(self, token: str) -> Player | None:
        """The guest of a session token, if they can still come back to a game."""
        player = self.guest_sessions.get(_hash(token))
        if player is None or not self.games.is_playing(player):
            return None
        return player

    async def handle_login_guest(self, client: Client, msg: dict[str, Any]) -> None:
        if not self.guests_enabled:
            raise P.ProtocolError(P.UNAVAILABLE, "Guest play is switched off on this server.")
        if client.identity is not None:
            raise P.ProtocolError(P.CONFLICT, "You are already logged in.")
        nick = P.get_str(msg, "nickname", max_len=16, min_len=3)
        assert nick is not None
        if not NICK_RE.match(nick):
            raise P.ProtocolError(P.BAD_MESSAGE, "A nickname has 3-16 letters, digits or '_'.")
        name = f"Guest_{nick}"
        if self.name_in_use(name):
            raise P.ProtocolError(P.CONFLICT, "This name is being used right now. Please choose another one.")
        player = Player(new_guest_id(), name, "guest")
        token = secrets.token_urlsafe(32)
        player.session = token
        self.guest_sessions[_hash(token)] = player
        self.presence.attach(player, client)
        log.info("event=guest_login conn=%s", client.conn_id)
        self.changed()
        await client.send(P.reply(msg, "logged_in", player=player.public(), session_token=token))

    # ------------------------------------------------------------------ quick match
    @staticmethod
    def _rating(p: Player) -> int:
        return p.rating if p.rating is not None else 1200

    def _range(self, entry: QueueEntry, now: float) -> int:
        steps = int((now - entry.since) / RATED_RANGE_EVERY)
        return min(RATED_RANGE_MAX, RATED_RANGE_START + RATED_RANGE_STEP * steps)

    def _compatible(self, a: QueueEntry, b: QueueEntry, now: float) -> bool:
        if a.tc != b.tc or a.rated != b.rated or a.player.player_id == b.player.player_id:
            return False
        if not a.rated:
            return True
        diff = abs(self._rating(a.player) - self._rating(b.player))
        return diff <= min(self._range(a, now), self._range(b, now))

    async def _pair(self, a: QueueEntry, b: QueueEntry, request: dict[str, Any] | None = None,
                    client: Client | None = None) -> None:
        self.queue = [e for e in self.queue if e is not a and e is not b]
        if client is not None and request is not None:
            await client.send(P.reply(request, "matchmaking_found"))
            await self.presence.send(b.player, {"type": "matchmaking_found"})
        else:
            for e in (a, b):
                await self.presence.send(e.player, {"type": "matchmaking_found"})
        white, black = (a.player, b.player) if self.rng.random() < 0.5 else (b.player, a.player)
        await self._cancel_challenges_of(a.player, "busy")
        await self._cancel_challenges_of(b.player, "busy")
        await self.games.create_game(white, black, a.tc, a.rated)
        self.changed()

    async def handle_join(self, client: Client, msg: dict[str, Any]) -> None:
        player: Player = client.identity
        tc = TimeControl.from_request(P.get_obj(msg, "time_control"))
        rated = bool(P.get_bool(msg, "rated", optional=True, default=False))
        if rated and not self.rated_enabled:
            raise P.ProtocolError(P.UNAVAILABLE, "Rated games are switched off on this server.")
        if rated and player.is_guest:
            raise P.ProtocolError(P.FORBIDDEN, "Rated games are for registered players.")
        if self.games.is_playing(player):
            raise P.ProtocolError(P.CONFLICT, "You are already playing a game.")
        if any(e.player.player_id == player.player_id for e in self.queue):
            raise P.ProtocolError(P.CONFLICT, "You are already waiting for an opponent.")
        entry = QueueEntry(player, tc, rated, self.now())
        now = self.now()
        opponent = next((e for e in self.queue if self._compatible(entry, e, now)
                         and self.presence.is_online(e.player)), None)
        if opponent is None:
            self.queue.append(entry)
            self.changed()
            await client.send(P.reply(msg, "matchmaking_waiting", time_control=tc.to_json(), rated=rated))
            return
        await self._pair(entry, opponent, msg, client)

    async def handle_cancel(self, client: Client, msg: dict[str, Any]) -> None:
        player: Player = client.identity
        before = len(self.queue)
        self.queue = [e for e in self.queue if e.player.player_id != player.player_id]
        if len(self.queue) == before:
            raise P.ProtocolError(P.CONFLICT, "You are not waiting for an opponent.")
        self.changed()
        await client.send(P.reply(msg, "ok"))

    async def match_waiting(self) -> int:
        """Pairs waiting rated players whose ranges now overlap. Returns pairs made."""
        made, now = 0, self.now()
        i = 0
        while i < len(self.queue):
            a = self.queue[i]
            b = next((e for e in self.queue[i + 1:] if self._compatible(a, e, now)), None)
            if b is None:
                i += 1
                continue
            await self._pair(a, b)
            made += 1
        return made

    async def _match_loop(self) -> None:
        while True:
            await asyncio.sleep(2.0)
            try:
                await self.match_waiting()
            except Exception:
                log.exception("event=matcher_error")

    # ------------------------------------------------------------------ challenges
    def _open_with(self, player: Player) -> list[Challenge]:
        return [c for c in self.challenges.values()
                if player.player_id in (c.sender.player_id, c.receiver.player_id)]

    def _challenge_for(self, msg: dict[str, Any]) -> Challenge:
        cid = P.get_str(msg, "challenge_id", max_len=32, min_len=1)
        ch = self.challenges.get(cid or "")
        if ch is None:
            raise P.ProtocolError(P.NOT_FOUND, "This challenge is no longer open.")
        return ch

    def _drop(self, ch: Challenge) -> None:
        self.challenges.pop(ch.challenge_id, None)
        if ch.timer is not None:
            ch.timer.cancel()
            ch.timer = None

    async def _expire(self, cid: str) -> None:
        ch = self.challenges.get(cid)
        if ch is None:
            return
        self._drop(ch)
        msg = {"type": "challenge_expired", "challenge_id": cid}
        await self.presence.send(ch.sender, msg)
        await self.presence.send(ch.receiver, msg)

    async def _cancel_challenges_of(self, player: Player, reason: str) -> None:
        for ch in self._open_with(player):
            self._drop(ch)
            other = ch.receiver if ch.sender.player_id == player.player_id else ch.sender
            await self.presence.send(other, {"type": "challenge_cancelled", "challenge_id": ch.challenge_id,
                                             "reason": reason})

    def _online_player(self, name: str) -> Player | None:
        lower = name.lower()
        for p, _ in self.presence.online.values():
            if p.name.lower() == lower:
                return p
        return None

    async def handle_challenge(self, client: Client, msg: dict[str, Any]) -> None:
        me: Player = client.identity
        name = P.get_str(msg, "opponent", max_len=32, min_len=1)
        tc = TimeControl.from_request(P.get_obj(msg, "time_control"))
        rated = bool(P.get_bool(msg, "rated", optional=True, default=False))
        target = self._online_player(name or "")
        if target is None:
            raise P.ProtocolError(P.NOT_FOUND, "This player is not online.")
        if target.player_id == me.player_id:
            raise P.ProtocolError(P.BAD_MESSAGE, "You cannot challenge yourself.")
        if rated and not self.rated_enabled:
            raise P.ProtocolError(P.UNAVAILABLE, "Rated games are switched off on this server.")
        if rated and (me.is_guest or target.is_guest):
            raise P.ProtocolError(P.FORBIDDEN, "Rated games are for two registered players.")
        if self.games.is_playing(me):
            raise P.ProtocolError(P.CONFLICT, "You are already playing a game.")
        if self.games.is_playing(target):
            raise P.ProtocolError(P.CONFLICT, f"{target.name} is playing a game right now.")
        if any(c.sender.player_id == me.player_id and c.receiver.player_id == target.player_id
               for c in self.challenges.values()):
            raise P.ProtocolError(P.CONFLICT, f"You have already challenged {target.name}.")
        if sum(1 for c in self.challenges.values() if c.sender.player_id == me.player_id) >= MAX_OUTGOING_CHALLENGES:
            raise P.ProtocolError(P.CONFLICT, "You have too many open challenges.")
        if sum(1 for c in self.challenges.values() if c.receiver.player_id == target.player_id) >= MAX_INCOMING_CHALLENGES:
            raise P.ProtocolError(P.CONFLICT, f"{target.name} has too many challenges right now.")
        ch = Challenge(secrets.token_urlsafe(9), me, target, tc, rated)
        self.challenges[ch.challenge_id] = ch
        ch.timer = asyncio.get_running_loop().call_later(
            CHALLENGE_SECONDS, lambda: asyncio.ensure_future(self._expire(ch.challenge_id)))
        log.info("event=challenge conn=%s rated=%s tc=%s", client.conn_id, rated, tc.pgn())
        await client.send(P.reply(msg, "challenge_sent", challenge=ch.public()))
        await self.presence.send(target, {"type": "challenge_received", "challenge": ch.public()})

    async def handle_challenge_accept(self, client: Client, msg: dict[str, Any]) -> None:
        me: Player = client.identity
        ch = self._challenge_for(msg)
        if ch.receiver.player_id != me.player_id:
            raise P.ProtocolError(P.FORBIDDEN, "This challenge is not for you.")
        if not self.presence.is_online(ch.sender):
            self._drop(ch)
            raise P.ProtocolError(P.CONFLICT, f"{ch.sender.name} has left.")
        if self.games.is_playing(ch.sender) or self.games.is_playing(me):
            self._drop(ch)
            raise P.ProtocolError(P.CONFLICT, "One of you is already playing.")
        self._drop(ch)
        self.queue = [e for e in self.queue if e.player.player_id not in (me.player_id, ch.sender.player_id)]
        await client.send(P.reply(msg, "ok", challenge_id=ch.challenge_id))
        await self.presence.send(ch.sender, {"type": "challenge_accepted", "challenge_id": ch.challenge_id})
        await self._cancel_challenges_of(me, "busy")
        await self._cancel_challenges_of(ch.sender, "busy")
        white, black = (ch.sender, me) if self.rng.random() < 0.5 else (me, ch.sender)
        await self.games.create_game(white, black, ch.tc, ch.rated)
        self.changed()

    async def handle_challenge_decline(self, client: Client, msg: dict[str, Any]) -> None:
        me: Player = client.identity
        ch = self._challenge_for(msg)
        if ch.receiver.player_id != me.player_id:
            raise P.ProtocolError(P.FORBIDDEN, "This challenge is not for you.")
        self._drop(ch)
        await client.send(P.reply(msg, "ok", challenge_id=ch.challenge_id))
        await self.presence.send(ch.sender, {"type": "challenge_declined", "challenge_id": ch.challenge_id})

    async def handle_challenge_cancel(self, client: Client, msg: dict[str, Any]) -> None:
        me: Player = client.identity
        ch = self._challenge_for(msg)
        if ch.sender.player_id != me.player_id:
            raise P.ProtocolError(P.FORBIDDEN, "Only the challenger can cancel.")
        self._drop(ch)
        await client.send(P.reply(msg, "ok", challenge_id=ch.challenge_id))
        await self.presence.send(ch.receiver, {"type": "challenge_cancelled", "challenge_id": ch.challenge_id,
                                               "reason": "cancelled"})

    # ------------------------------------------------------------------ leaving
    async def player_left(self, player: Player) -> None:
        """The player is gone (disconnected or logged out)."""
        self.queue = [e for e in self.queue if e.player.player_id != player.player_id]
        await self._cancel_challenges_of(player, "left")
        if not self.games.is_playing(player):
            for key, p in list(self.guest_sessions.items()):
                if p.player_id == player.player_id:
                    del self.guest_sessions[key]
        self.changed()

    async def on_disconnect(self, client: Client) -> None:
        self.subscribers.pop(client.conn_id, None)
        player = client.identity
        if player is not None and not self.presence.is_online(player):
            await self.player_left(player)
