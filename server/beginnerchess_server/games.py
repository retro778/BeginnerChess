"""Authoritative online games: moves, clocks, draws, resignation and results.

Everything happens on the event loop; a request is checked and applied
without any ``await`` in between, so two requests can never interleave on the
same game. Events are sent afterwards.

Clock policy (also in docs/PROTOCOL.md):
* Each side must play its first move within ``first_move_seconds``;
  otherwise the game is *aborted* (no result).
* After both first moves, the clock of the side to move runs from the moment
  the opponent's move was accepted (server time, monotonic). After a move the
  increment is added.
* Running out of time loses, unless the opponent cannot possibly checkmate
  (then it is a draw).

Disconnection: the clocks keep running. The opponent is told at once; after
``grace_seconds`` the player who is still there may claim the win or a draw
(termination "abandoned"). A player who comes back in time simply continues
(the server sends the full game state again).

Server restart recovery: every running game is saved after each move. After a
restart, games between two accounts are restored with the clock times of the
last saved move (the downtime is not charged) and wait for the players to
reconnect (the disconnection rules then apply). Games involving a guest (whose
identity does not survive a restart) and games where not both sides have moved
yet are cancelled without a result. No win is ever awarded because of a
restart.
"""

from __future__ import annotations

import asyncio
import logging
import secrets
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from . import protocol as P
from .chess_rules import START_FEN, Board, Move
from .connections import Client
from .players import Player, Presence

log = logging.getLogger("beginnerchess.games")

#: Time controls offered to players: initial minutes x increments in seconds.
ALLOWED_MINUTES = (3, 5, 10, 15, 30)
ALLOWED_INCREMENTS = (0, 2, 5, 10)

RESULT_TEXT = {"1-0": "White wins", "0-1": "Black wins", "1/2-1/2": "Draw"}


@dataclass(frozen=True)
class TimeControl:
    initial_ms: int
    increment_ms: int

    @staticmethod
    def from_request(obj: dict[str, Any] | None) -> "TimeControl":
        """Validates a client's {"initial_seconds", "increment_seconds"}."""
        if obj is None:
            raise P.ProtocolError(P.BAD_MESSAGE, "'time_control' is missing.")
        initial = P.get_int(obj, "initial_seconds", lo=1, hi=7200)
        increment = P.get_int(obj, "increment_seconds", lo=0, hi=600)
        assert initial is not None and increment is not None
        if initial not in [m * 60 for m in ALLOWED_MINUTES] or increment not in ALLOWED_INCREMENTS:
            raise P.ProtocolError(P.BAD_MESSAGE, "Time controls: 3, 5, 10, 15 or 30 minutes "
                                                 "with 0, 2, 5 or 10 seconds increment.")
        return TimeControl(initial * 1000, increment * 1000)

    def to_json(self) -> dict[str, int]:
        return {"initial_seconds": self.initial_ms // 1000, "increment_seconds": self.increment_ms // 1000}

    def pgn(self) -> str:
        return f"{self.initial_ms // 1000}+{self.increment_ms // 1000}"


def colour_name(c: str) -> str:
    return "white" if c == "w" else "black"


def other(c: str) -> str:
    return "b" if c == "w" else "w"


@dataclass(eq=False)
class Game:
    game_id: str
    white: Player
    black: Player
    tc: TimeControl
    rated: bool
    first_move_ms: int
    board: Board = field(default_factory=Board)
    ucis: list[str] = field(default_factory=list)
    sans: list[str] = field(default_factory=list)
    status: str = "active"                 # active | finished | aborted
    result: str | None = None              # "1-0" | "0-1" | "1/2-1/2" (None if aborted)
    termination: str | None = None
    clock_ms: dict[str, int] = field(default_factory=dict)
    turn_started: float = 0.0              # monotonic time the side to move started thinking
    draw_offer: str | None = None          # colour that offered a draw
    last_offer_ply: dict[str, int] = field(default_factory=lambda: {"w": -1, "b": -1})
    seq: int = 0                           # increases with every change of state
    started_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat(timespec="seconds"))
    ended_at: str | None = None
    timer: asyncio.TimerHandle | None = None
    away: dict[str, float] = field(default_factory=dict)   # colour -> monotonic time it disconnected

    def __post_init__(self) -> None:
        self.clock_ms = {"w": self.tc.initial_ms, "b": self.tc.initial_ms}

    # ------------------------------------------------------------------ queries
    @property
    def ply(self) -> int:
        return len(self.ucis)

    @property
    def clocks_running(self) -> bool:
        return self.status == "active" and self.ply >= 2

    def has_account(self) -> bool:
        """True if at least one player has an account (only such games are stored)."""
        return self.white.account_id is not None or self.black.account_id is not None

    def colour_of(self, player: Player) -> str | None:
        if player is self.white or player.player_id == self.white.player_id:
            return "w"
        if player is self.black or player.player_id == self.black.player_id:
            return "b"
        return None

    def player(self, colour: str) -> Player:
        return self.white if colour == "w" else self.black

    def remaining_ms(self, colour: str, now: float) -> int:
        ms = self.clock_ms[colour]
        if self.clocks_running and self.board.turn == colour:
            ms -= int((now - self.turn_started) * 1000)
        return max(0, ms)

    def deadline(self) -> float | None:
        """Monotonic time at which the side to move runs out of time."""
        if self.status != "active":
            return None
        if self.ply < 2:
            return self.turn_started + self.first_move_ms / 1000
        return self.turn_started + self.clock_ms[self.board.turn] / 1000

    def clocks_json(self, now: float) -> dict[str, Any]:
        return {"white_ms": self.remaining_ms("w", now), "black_ms": self.remaining_ms("b", now),
                "running": self.board.turn if self.clocks_running else None,
                "first_move_ms": (max(0, int((self.deadline() - now) * 1000))
                                  if self.status == "active" and self.ply < 2 else None)}

    def snapshot(self, now: float, viewer: Player | None = None) -> dict[str, Any]:
        """The complete authoritative state (sent at start, on request, after reconnect)."""
        snap: dict[str, Any] = {
            "game_id": self.game_id, "seq": self.seq,
            "white": self.white.public(), "black": self.black.public(),
            "rated": self.rated, "time_control": self.tc.to_json(),
            "initial_fen": START_FEN, "moves": list(self.ucis), "san": list(self.sans),
            "fen": self.board.fen(), "ply": self.ply, "turn": self.board.turn,
            "in_check": self.board.in_check(),
            "status": self.status, "result": self.result, "termination": self.termination,
            "draw_offer": self.draw_offer,
            "can_claim_draw": self.status == "active" and (self.board.can_claim_threefold()
                                                          or self.board.can_claim_fifty_moves()),
            "clock": self.clocks_json(now),
            "away": {c: int(now - t) for c, t in self.away.items()},   # seconds disconnected
        }
        if viewer is not None:
            snap["your_color"] = self.colour_of(viewer)
        return snap

    def pgn(self) -> str:
        date = self.started_at[:10].replace("-", ".")
        tags = [("Event", "BeginnerChess Online" + (" (rated)" if self.rated else "")),
                ("Site", "BeginnerChess Online"), ("Date", date), ("Round", "-"),
                ("White", self.white.name), ("Black", self.black.name),
                ("Result", self.result or "*")]
        if self.rated and self.white.rating is not None and self.black.rating is not None:
            tags += [("WhiteElo", str(self.white.rating)), ("BlackElo", str(self.black.rating))]
        tags += [("TimeControl", self.tc.pgn()), ("Termination", self.termination or "unterminated"),
                 ("PlyCount", str(self.ply))]
        head = "".join(f'[{k} "{v.replace(chr(92), "").replace(chr(34), "")}"]\n' for k, v in tags)
        words = []
        for i, san in enumerate(self.sans):
            if i % 2 == 0:
                words.append(f"{i // 2 + 1}.")
            words.append(san)
        words.append(self.result or "*")
        lines, line = [], ""
        for w in words:
            if line and len(line) + 1 + len(w) > 79:
                lines.append(line)
                line = w
            else:
                line = f"{line} {w}" if line else w
        lines.append(line)
        return head + "\n" + "\n".join(lines) + "\n"


EndCallback = Callable[[Game], Awaitable[None]]


class GameManager:
    def __init__(self, presence: Presence, first_move_seconds: int = 30,
                 clock: Callable[[], float] = time.monotonic, grace_seconds: int = 60):
        self.presence = presence
        self.first_move_ms = first_move_seconds * 1000
        self.grace_seconds = grace_seconds
        self.store = None                               # Database: running games are saved
        self.now = clock
        self.games: dict[str, Game] = {}
        self.active_by_player: dict[str, str] = {}     # player_id -> game_id
        self.on_game_end: list[EndCallback] = []
        self.finished_kept = 200                        # recently finished games kept in memory

    # ------------------------------------------------------------------ setup
    def register_routes(self, server) -> None:
        server.route("move", self.handle_move, auth="player")
        server.route("game_state", self.handle_game_state, auth="player")
        server.route("resign", self.handle_resign, auth="player")
        server.route("offer_draw", self.handle_offer_draw, auth="player")
        server.route("accept_draw", self.handle_accept_draw, auth="player")
        server.route("decline_draw", self.handle_decline_draw, auth="player")
        server.route("claim_draw", self.handle_claim_draw, auth="player")
        server.route("abort", self.handle_abort, auth="player")
        server.route("claim_abandonment", self.handle_claim_abandonment, auth="player")

    def is_playing(self, player: Player) -> bool:
        return player.player_id in self.active_by_player

    def active_game_of(self, player: Player) -> Game | None:
        gid = self.active_by_player.get(player.player_id)
        return self.games.get(gid) if gid else None

    async def create_game(self, white: Player, black: Player, tc: TimeControl, rated: bool) -> Game:
        if self.is_playing(white) or self.is_playing(black):
            raise P.ProtocolError(P.CONFLICT, "A player is already in a game.")
        game = Game(game_id=secrets.token_urlsafe(9), white=white, black=black, tc=tc,
                    rated=rated, first_move_ms=self.first_move_ms)
        game.turn_started = self.now()
        self.games[game.game_id] = game
        self.active_by_player[white.player_id] = game.game_id
        self.active_by_player[black.player_id] = game.game_id
        self._schedule(game)
        await self._persist(game)
        log.info("event=game_started game=%s rated=%s tc=%s", game.game_id, rated, tc.pgn())
        now = self.now()
        for p in (white, black):
            await self.presence.send(p, {"type": "game_started", "game": game.snapshot(now, p)})
        return game

    # ------------------------------------------------------------------ helpers
    def _game_for(self, client: Client, msg: dict[str, Any]) -> tuple[Game, str]:
        gid = P.get_str(msg, "game_id", max_len=32, min_len=1)
        game = self.games.get(gid or "")
        player: Player = client.identity
        colour = game.colour_of(player) if game else None
        if game is None or colour is None:
            # Same answer for "no such game" and "not your game": ids are not guessable,
            # and nobody learns whether a game exists.
            raise P.ProtocolError(P.NOT_FOUND, "No such game.")
        return game, colour

    @staticmethod
    def _require_active(game: Game) -> None:
        if game.status != "active":
            raise P.ProtocolError(P.GAME_OVER, "The game is over.", result=game.result,
                                  termination=game.termination)

    async def _broadcast(self, game: Game, msg: dict[str, Any], requester: Player | None = None,
                         request: dict[str, Any] | None = None) -> None:
        for p in (game.white, game.black):
            out = dict(msg)
            if requester is not None and p.player_id == requester.player_id and request is not None \
                    and request.get("request_id") is not None:
                out["request_id"] = request["request_id"]
            await self.presence.send(p, out)

    def _schedule(self, game: Game) -> None:
        if game.timer is not None:
            game.timer.cancel()
            game.timer = None
        deadline = game.deadline()
        if deadline is None:
            return
        loop = asyncio.get_running_loop()
        delay = max(0.0, deadline - self.now())
        game.timer = loop.call_later(delay + 0.005,
                                     lambda: asyncio.ensure_future(self.check_time(game)))

    async def check_time(self, game: Game) -> bool:
        """Ends the game if the side to move has run out of time. True if it ended."""
        if game.status != "active":
            return False
        deadline = game.deadline()
        if deadline is None or self.now() < deadline:
            self._schedule(game)
            return False
        loser = game.board.turn
        if game.ply < 2:
            await self._finish(game, None, "first_move_timeout", status="aborted")
        elif game.board.has_insufficient_material(other(loser)):
            await self._finish(game, "1/2-1/2", "timeout_vs_insufficient_material")
        else:
            await self._finish(game, "0-1" if loser == "w" else "1-0", "timeout")
        return True

    async def _finish(self, game: Game, result: str | None, termination: str, *,
                      status: str = "finished", requester: Player | None = None,
                      request: dict[str, Any] | None = None) -> None:
        now = self.now()
        if game.clocks_running:                      # freeze the clock of the side to move
            game.clock_ms[game.board.turn] = game.remaining_ms(game.board.turn, now)
        game.status, game.result, game.termination = status, result, termination
        game.ended_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
        game.draw_offer = None
        game.seq += 1
        if game.timer is not None:
            game.timer.cancel()
            game.timer = None
        for p in (game.white, game.black):
            if self.active_by_player.get(p.player_id) == game.game_id:
                del self.active_by_player[p.player_id]
        log.info("event=game_over game=%s status=%s result=%s termination=%s plies=%d",
                 game.game_id, status, result, termination, game.ply)
        await self._broadcast(game, {"type": "game_over", "game_id": game.game_id, "seq": game.seq,
                                     "status": status, "result": result, "termination": termination,
                                     "clock": game.clocks_json(now), "pgn": game.pgn()},
                              requester, request)
        for callback in self.on_game_end:
            try:
                await callback(game)
            except Exception:
                log.exception("event=game_end_callback_error game=%s", game.game_id)
        self._forget_old_games()

    def _forget_old_games(self) -> None:
        done = [g for g in self.games.values() if g.status != "active"]
        for g in done[:-self.finished_kept] if len(done) > self.finished_kept else []:
            del self.games[g.game_id]

    # ------------------------------------------------------------------ requests
    async def handle_game_state(self, client: Client, msg: dict[str, Any]) -> None:
        game, _ = self._game_for(client, msg)
        await client.send(P.reply(msg, "game_state", game=game.snapshot(self.now(), client.identity)))

    async def handle_move(self, client: Client, msg: dict[str, Any]) -> None:
        game, colour = self._game_for(client, msg)
        player: Player = client.identity
        uci = P.get_str(msg, "move", max_len=5, min_len=4)
        expected = P.get_int(msg, "expected_ply", lo=0, hi=10000)
        claim = P.get_bool(msg, "claim_draw", optional=True, default=False)
        assert uci is not None and expected is not None

        # A retry of a move that was already accepted: answer again, do not play twice.
        if expected == game.ply - 1 and game.ucis and game.ucis[-1] == uci \
                and (game.ply - 1) % 2 == (0 if colour == "w" else 1):
            await client.send(P.reply(msg, "move_accepted", duplicate=True,
                                      **self._move_fields(game, self.now())))
            return
        self._require_active(game)
        if await self.check_time(game):           # the clock ran out before this request
            raise P.ProtocolError(P.GAME_OVER, "Your time is up.", result=game.result,
                                  termination=game.termination)
        if game.board.turn != colour:
            raise P.ProtocolError(P.NOT_YOUR_TURN, "It is not your turn.", current_ply=game.ply)
        if expected != game.ply:
            raise P.ProtocolError(P.CONFLICT, "The game has moved on - please reload it.",
                                  current_ply=game.ply)
        try:
            move = Move.from_uci(uci)
        except ValueError as err:
            raise P.ProtocolError(P.BAD_MESSAGE, f"Invalid move: {err}.") from None
        if not game.board.is_legal(move):
            raise P.ProtocolError(P.ILLEGAL_MOVE, "That move is not allowed.", current_ply=game.ply)

        # ---- accepted: update clock, board, offers (no await until the state is consistent)
        now = self.now()
        if game.clocks_running:
            game.clock_ms[colour] = game.remaining_ms(colour, now) + game.tc.increment_ms
        san = game.board.san(move)
        game.board.push(move)
        game.ucis.append(move.uci())
        game.sans.append(san)
        if game.draw_offer == other(colour):        # moving instead of answering declines
            game.draw_offer = None
        game.turn_started = now
        game.seq += 1
        self._schedule(game)
        await self._persist(game)

        ending = game.board.automatic_end()
        if ending is None and claim:
            if game.board.can_claim_threefold():
                ending = ("1/2-1/2", "threefold_repetition")
            elif game.board.can_claim_fifty_moves():
                ending = ("1/2-1/2", "fifty_moves")
        await self._broadcast(game, {"type": "move_accepted", **self._move_fields(game, now)},
                              player, msg)
        if ending is not None:
            await self._finish(game, ending[0], ending[1])

    def _move_fields(self, game: Game, now: float) -> dict[str, Any]:
        return {"game_id": game.game_id, "seq": game.seq, "ply": game.ply,
                "move": game.ucis[-1] if game.ucis else None,
                "san": game.sans[-1] if game.sans else None,
                "fen": game.board.fen(), "turn": game.board.turn, "in_check": game.board.in_check(),
                "draw_offer": game.draw_offer,
                "can_claim_draw": game.status == "active" and (game.board.can_claim_threefold()
                                                              or game.board.can_claim_fifty_moves()),
                "clock": game.clocks_json(now)}

    async def handle_resign(self, client: Client, msg: dict[str, Any]) -> None:
        game, colour = self._game_for(client, msg)
        self._require_active(game)
        if game.ply < 2:      # nothing has happened yet: no result, no rating change
            await self._finish(game, None, "aborted_by_player", status="aborted",
                               requester=client.identity, request=msg)
        else:
            await self._finish(game, "0-1" if colour == "w" else "1-0", "resignation",
                               requester=client.identity, request=msg)

    async def handle_abort(self, client: Client, msg: dict[str, Any]) -> None:
        game, _ = self._game_for(client, msg)
        self._require_active(game)
        if game.ply >= 2:
            raise P.ProtocolError(P.CONFLICT, "A game can only be aborted before both sides have moved.")
        await self._finish(game, None, "aborted_by_player", status="aborted",
                           requester=client.identity, request=msg)

    async def handle_offer_draw(self, client: Client, msg: dict[str, Any]) -> None:
        game, colour = self._game_for(client, msg)
        self._require_active(game)
        if game.draw_offer == other(colour):        # both want a draw
            await self._finish(game, "1/2-1/2", "agreement", requester=client.identity, request=msg)
            return
        if game.draw_offer == colour:
            raise P.ProtocolError(P.CONFLICT, "You have already offered a draw.")
        if game.last_offer_ply[colour] == game.ply:
            raise P.ProtocolError(P.CONFLICT, "You can offer a draw again after the next move.")
        game.draw_offer = colour
        game.last_offer_ply[colour] = game.ply
        game.seq += 1
        await client.send(P.reply(msg, "ok", game_id=game.game_id, seq=game.seq))
        await self.presence.send(game.player(other(colour)),
                                 {"type": "draw_offered", "game_id": game.game_id, "seq": game.seq,
                                  "by": colour_name(colour)})

    async def handle_accept_draw(self, client: Client, msg: dict[str, Any]) -> None:
        game, colour = self._game_for(client, msg)
        self._require_active(game)
        if game.draw_offer != other(colour):
            raise P.ProtocolError(P.CONFLICT, "There is no draw offer to accept.")
        await self._finish(game, "1/2-1/2", "agreement", requester=client.identity, request=msg)

    async def handle_decline_draw(self, client: Client, msg: dict[str, Any]) -> None:
        game, colour = self._game_for(client, msg)
        self._require_active(game)
        if game.draw_offer != other(colour):
            raise P.ProtocolError(P.CONFLICT, "There is no draw offer to decline.")
        game.draw_offer = None
        game.seq += 1
        await client.send(P.reply(msg, "ok", game_id=game.game_id, seq=game.seq))
        await self.presence.send(game.player(other(colour)),
                                 {"type": "draw_declined", "game_id": game.game_id, "seq": game.seq})

    async def handle_claim_draw(self, client: Client, msg: dict[str, Any]) -> None:
        game, colour = self._game_for(client, msg)
        self._require_active(game)
        if game.board.turn != colour:
            raise P.ProtocolError(P.NOT_YOUR_TURN, "Only the player to move can claim a draw.")
        if game.board.can_claim_threefold():
            await self._finish(game, "1/2-1/2", "threefold_repetition", requester=client.identity, request=msg)
        elif game.board.can_claim_fifty_moves():
            await self._finish(game, "1/2-1/2", "fifty_moves", requester=client.identity, request=msg)
        else:
            raise P.ProtocolError(P.CONFLICT, "No draw can be claimed in this position.")

    # ------------------------------------------------------------------ persistence
    def _record(self, game: Game) -> dict[str, Any]:
        return {"id": game.game_id, "white_user_id": game.white.account_id,
                "black_user_id": game.black.account_id, "white_name": game.white.name,
                "black_name": game.black.name, "rated": game.rated, "initial_ms": game.tc.initial_ms,
                "increment_ms": game.tc.increment_ms, "moves": " ".join(game.ucis),
                "final_fen": game.board.fen(), "started_at": game.started_at,
                "white_key": game.white.player_id, "black_key": game.black.player_id,
                "white_ms": game.clock_ms["w"], "black_ms": game.clock_ms["b"],
                "draw_offer": game.draw_offer, "seq": game.seq}

    async def _persist(self, game: Game) -> None:
        if self.store is None or game.status != "active" or not game.has_account():
            return                             # games between guests are never stored
        try:
            await self.store.save_active_game(self._record(game))
        except Exception:                      # a full disk must not stop the game
            log.exception("event=persist_error game=%s", game.game_id)

    async def restore(self, db, user_player) -> tuple[int, int]:
        """After a restart: restores saved games (see the module notes).
        user_player(user_id) -> Player or None. Returns (restored, cancelled)."""
        restored = cancelled = 0
        for row in await db.active_games():
            white = await user_player(row["white_user_id"]) if row["white_user_id"] else None
            black = await user_player(row["black_user_id"]) if row["black_user_id"] else None
            moves = row["moves"].split()
            tc = TimeControl(row["initial_ms"], row["increment_ms"])
            if row["white_user_id"] is None and row["black_user_id"] is None:
                await db.delete_game(row["id"])          # nobody's history (stored by an older version)
                cancelled += 1
                continue
            if white is None or black is None or len(moves) < 2:
                await db.save_game({"id": row["id"], "white_user_id": row["white_user_id"],
                                    "black_user_id": row["black_user_id"], "white_name": row["white_name"],
                                    "black_name": row["black_name"], "rated": bool(row["rated"]),
                                    "initial_ms": row["initial_ms"], "increment_ms": row["increment_ms"],
                                    "status": "aborted", "result": None, "termination": "server_restart",
                                    "moves": row["moves"], "final_fen": row["final_fen"], "pgn": None,
                                    "started_at": row["started_at"],
                                    "ended_at": datetime.now(timezone.utc).isoformat(timespec="seconds")})
                cancelled += 1
                continue
            game = Game(game_id=row["id"], white=white, black=black, tc=tc, rated=bool(row["rated"]),
                        first_move_ms=self.first_move_ms, started_at=row["started_at"])
            for uci in moves:
                m = Move.from_uci(uci)
                game.sans.append(game.board.san(m))
                game.board.push(m)
                game.ucis.append(uci)
            game.clock_ms = {"w": row["white_ms"], "b": row["black_ms"]}
            game.draw_offer = row["draw_offer"]
            game.seq = row["seq"] + 1
            now = self.now()
            game.turn_started = now                 # the downtime is not charged
            game.away = {"w": now, "b": now}        # nobody is connected yet
            self.games[game.game_id] = game
            self.active_by_player[white.player_id] = game.game_id
            self.active_by_player[black.player_id] = game.game_id
            self._schedule(game)
            restored += 1
        log.info("event=games_restored restored=%d cancelled=%d", restored, cancelled)
        return restored, cancelled

    # ------------------------------------------------------------------ connection loss
    async def player_disconnected(self, player: Player) -> None:
        game = self.active_game_of(player)
        if game is None or game.status != "active":
            return
        colour = game.colour_of(player)
        game.away[colour] = self.now()
        await self.presence.send(game.player(other(colour)),
                                 {"type": "opponent_disconnected", "game_id": game.game_id,
                                  "grace_seconds": self.grace_seconds})

    async def player_connected(self, player: Player) -> None:
        """A player logged in (or came back): continue a running game."""
        game = self.active_game_of(player)
        if game is None or game.status != "active":
            return
        colour = game.colour_of(player)
        # Use the new identity object (fresh rating) from now on.
        if colour == "w":
            game.white = player
        else:
            game.black = player
        was_away = game.away.pop(colour, None) is not None
        await self.presence.send(player, {"type": "game_resumed", "game": game.snapshot(self.now(), player)})
        if was_away:
            await self.presence.send(game.player(other(colour)),
                                     {"type": "opponent_reconnected", "game_id": game.game_id})

    async def handle_claim_abandonment(self, client: Client, msg: dict[str, Any]) -> None:
        game, colour = self._game_for(client, msg)
        self._require_active(game)
        outcome = P.get_str(msg, "outcome", max_len=4, min_len=3)
        if outcome not in ("win", "draw"):
            raise P.ProtocolError(P.BAD_MESSAGE, "'outcome' must be 'win' or 'draw'.")
        since = game.away.get(other(colour))
        if since is None:
            raise P.ProtocolError(P.CONFLICT, "Your opponent is connected.")
        left = self.grace_seconds - (self.now() - since)
        if left > 0:
            raise P.ProtocolError(P.CONFLICT, "Your opponent may still come back.", seconds_left=int(left) + 1)
        if outcome == "win":
            await self._finish(game, "1-0" if colour == "w" else "0-1", "abandoned",
                               requester=client.identity, request=msg)
        else:
            await self._finish(game, "1/2-1/2", "abandoned", requester=client.identity, request=msg)
