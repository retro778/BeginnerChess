"""The server core: accepts WebSocket connections, enforces the handshake and
limits, and dispatches requests to handlers.

Concurrency model: one asyncio event loop; every connection is one task.
Shared state is only touched from the loop (no locks needed). Blocking work
(database, password hashing) is moved to worker threads with
``asyncio.to_thread`` by the modules that need it.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from http import HTTPStatus
from typing import Any

from websockets.asyncio.server import Server, ServerConnection, serve
from websockets.datastructures import Headers
from websockets.exceptions import ConnectionClosed
from websockets.http11 import Request, Response

from . import PROTOCOL_VERSION, __version__
from . import protocol as P
from .config import Config
from .connections import Client, ConnectionRegistry, TokenBucket, client_ip
from .limits import SlidingWindow
from .games import GameManager
from .lobby import Lobby
from .accounts import Accounts, player_from_user
from .ratings import Ratings
from .administration import Admin
from .persistence import Database
from .players import Presence

log = logging.getLogger("beginnerchess.server")

Handler = Callable[[Client, dict[str, Any]], Awaitable[None]]


def log_event(event: str, level: int = logging.INFO, **fields: Any) -> None:
    """Structured log line: ``event=name key=value ...``. Never pass secrets here."""
    parts = [f"event={event}"]
    for key, value in fields.items():
        text = str(value)
        if any(c in text for c in ' "=\n'):
            text = json.dumps(text)
        parts.append(f"{key}={text}")
    log.log(level, " ".join(parts))


@dataclass
class Route:
    handler: Handler
    #: "none": allowed right after hello; "player": needs a guest or account login
    auth: str = "none"
    #: optional extra limit for expensive/abusable requests, counted per scope
    limit: SlidingWindow | None = None
    scope: str = "conn"                 # "ip", "player" or "conn"


class ChessServer:
    def __init__(self, config: Config):
        self.config = config
        self.registry = ConnectionRegistry(config.max_connections, config.max_connections_per_ip)
        self.routes: dict[str, Route] = {}
        self.started_at = time.monotonic()
        self._server: Server | None = None
        self._stopping = False
        self.on_disconnect: list[Callable[[Client], Awaitable[None]]] = []
        self.connection_rate = SlidingWindow(config.new_connections_per_minute, 60.0)
        self._sweeper: asyncio.Task | None = None
        self.route("ping", self._handle_ping)
        self.route("server_info", self._handle_server_info)
        self.presence = Presence()
        self.games = GameManager(self.presence, config.first_move_seconds,
                                 grace_seconds=config.reconnect_grace_seconds)
        self.games.register_routes(self)
        self.on_disconnect.append(self._forget_presence)
        self.lobby = Lobby(self.presence, self.games, guests_enabled=config.guest_access_enabled,
                           rated_enabled=config.rated_games_enabled)
        self.lobby.register_routes(self)
        self.db = Database(config.database_path)
        self.accounts = Accounts(self.db, self.presence, registration_enabled=config.registration_enabled,
                                 session_days=config.session_days)
        self.accounts.register_routes(self)
        self.accounts.lobby = self.lobby
        self.games.on_game_end.append(self.accounts.on_game_end)       # store first ...
        self.ratings = Ratings(self.db, self.presence)
        self.games.on_game_end.append(self.ratings.on_game_end)        # ... then rate
        self.games.store = self.db
        self.admin = Admin(self)

    # ------------------------------------------------------------------ setup
    def route(self, mtype: str, handler: Handler, auth: str = "none",
              limit: tuple[int, float] | None = None, scope: str = "conn") -> None:
        if mtype in self.routes or mtype == "hello":
            raise ValueError(f"route {mtype} already defined")
        window = SlidingWindow(*limit) if limit else None
        self.routes[mtype] = Route(handler, auth, window, scope)

    async def _user_player(self, user_id: int):
        user = await self.db.user_by_id(user_id)
        return player_from_user(user) if user and user["status"] == "active" else None

    async def start(self, ssl_context: Any = None) -> Server:
        await self.games.restore(self.db, self._user_player)        # after a restart
        self.lobby.start()
        self._sweeper = asyncio.get_running_loop().create_task(self._sweep_loop())
        if self.config.admin_socket:
            await self.admin.start(self.config.admin_socket, self.config.admin_socket_mode)
        self._server = await serve(
            self._connection,
            self.config.listen_host,
            self.config.listen_port,
            process_request=self._process_request,
            max_size=self.config.max_message_size,
            max_queue=16,
            ping_interval=self.config.heartbeat_interval,
            ping_timeout=self.config.heartbeat_timeout,
            open_timeout=10,
            close_timeout=5,
            compression=None,          # keeps memory per connection small and predictable
            server_header="BeginnerChess",
            ssl=ssl_context,
        )
        log_event("server_started", host=self.config.listen_host, port=self.port,
                  version=__version__, protocol=PROTOCOL_VERSION)
        return self._server

    @property
    def port(self) -> int:
        assert self._server is not None
        return self._server.sockets[0].getsockname()[1]

    async def stop(self) -> None:
        """Graceful shutdown: tell every client, close connections, stop listening."""
        if self._server is None or self._stopping:
            return
        self._stopping = True
        self.lobby.stop()
        if self._sweeper is not None:
            self._sweeper.cancel()
        await self.admin.stop()
        self._server.close(close_connections=False)
        for game in self.games.games.values():          # no timer may fire during shutdown
            if game.timer is not None:
                game.timer.cancel()
                game.timer = None
        for client in list(self.registry.clients.values()):
            await client.send({"type": "server_shutdown",
                               "message": "The server is restarting. Please reconnect in a moment."})
            await client.ws.close(1001, "server shutdown")
        await self._server.wait_closed()
        self.accounts.hash_pool.shutdown(wait=False)
        self.db.close()
        log_event("server_stopped")

    # ------------------------------------------------------------------ HTTP
    def _process_request(self, connection: ServerConnection, request: Request) -> Response | None:
        path = request.path.split("?", 1)[0]
        if path == self.config.health_path:
            body = json.dumps({"status": "ok", "protocol_version": PROTOCOL_VERSION,
                               "server_version": __version__})
            return Response(HTTPStatus.OK.value, "OK",
                            Headers({"Content-Type": "application/json",
                                     "Cache-Control": "no-store",
                                     "Content-Length": str(len(body))}),
                            body.encode())
        if path != self.config.ws_path:
            return connection.respond(HTTPStatus.NOT_FOUND, "Not found\n")
        if self._stopping:
            return connection.respond(HTTPStatus.SERVICE_UNAVAILABLE, "Server is restarting\n")
        ip = self._ip_of(connection, request.headers)
        reason = self.registry.can_accept(ip)
        if reason is None and not self.connection_rate.allow(ip):
            reason = "too many new connections - please wait a minute"
        if reason is not None:
            log_event("connection_refused", logging.WARNING, ip=ip, reason=reason)
            return connection.respond(HTTPStatus.SERVICE_UNAVAILABLE, f"Refused: {reason}\n")
        return None

    def _ip_of(self, connection: ServerConnection, headers: Headers) -> str:
        return client_ip(connection.remote_address, headers.get("X-Forwarded-For"),
                         self.config.trusted_proxies)

    # ------------------------------------------------------------------ connection
    async def _connection(self, ws: ServerConnection) -> None:
        ip = self._ip_of(ws, ws.request.headers if ws.request else Headers())
        # Check again: several handshakes may have been accepted at the same time.
        if self.registry.can_accept(ip) is not None:
            await ws.close(1013, "try again later")
            return
        client = Client(ws=ws, ip=ip,
                        bucket=TokenBucket(self.config.rate_limit_burst, self.config.rate_limit_per_second))
        self.registry.add(client)
        log_event("connected", conn=client.conn_id, ip=ip, total=len(self.registry))
        try:
            if await self._handshake(client):
                await self._message_loop(client)
        except ConnectionClosed:
            pass
        except Exception:  # never let one connection take the server down
            log.exception("event=connection_error conn=%s", client.conn_id)
        finally:
            self.registry.remove(client)
            for callback in self.on_disconnect:
                try:
                    await callback(client)
                except Exception:
                    log.exception("event=disconnect_callback_error conn=%s", client.conn_id)
            log_event("disconnected", conn=client.conn_id, code=ws.close_code,
                      total=len(self.registry))

    async def _handshake(self, client: Client) -> bool:
        """The first message must be a compatible hello (within hello_timeout)."""
        try:
            text = await asyncio.wait_for(client.ws.recv(), self.config.hello_timeout)
        except TimeoutError:
            await client.send(P.error_message(P.HELLO_REQUIRED, "Send 'hello' first."))
            await client.ws.close(P.CLOSE_HELLO_TIMEOUT, "hello timeout")
            return False
        try:
            msg = P.parse_message(text)
            if msg["type"] != "hello":
                raise P.ProtocolError(P.HELLO_REQUIRED, "The first message must be 'hello'.")
            client.client_name, client.client_version = P.check_hello(msg)
        except P.ProtocolError as err:
            await client.send(P.error_message(err.code, err.message, _rid(text)))
            code = P.CLOSE_INCOMPATIBLE if err.code == P.INCOMPATIBLE_VERSION else 1008
            await client.ws.close(code, err.code)
            return False
        client.greeted = True
        await client.send(P.reply(msg, "welcome",
                                  protocol_version=PROTOCOL_VERSION,
                                  server_name="BeginnerChess Server",
                                  server_version=__version__,
                                  connection_id=client.conn_id,
                                  limits={"max_message_size": self.config.max_message_size,
                                          "heartbeat_seconds": self.config.heartbeat_interval},
                                  features=self.features()))
        log_event("hello", conn=client.conn_id, client=client.client_name,
                  client_version=client.client_version)
        return True

    def features(self) -> dict[str, bool]:
        return {"guests": self.config.guest_access_enabled,
                "registration": self.config.registration_enabled,
                "rated_games": self.config.rated_games_enabled}

    async def _message_loop(self, client: Client) -> None:
        async for text in client.ws:
            if not client.bucket.allow():
                await self._violation(client, P.ProtocolError(
                    P.RATE_LIMITED, "Too many messages - please slow down.", violation=True), None)
                continue
            msg: dict[str, Any] | None = None
            try:
                msg = P.parse_message(text)
                await self._dispatch(client, msg)
            except P.ProtocolError as err:
                await self._violation(client, err, msg.get("request_id") if msg else _rid(text))
            except ConnectionClosed:
                raise
            except Exception:
                log.exception("event=handler_error conn=%s type=%s", client.conn_id,
                              msg.get("type") if msg else "?")
                await client.send(P.error_message(P.INTERNAL_ERROR, "Something went wrong on the server.",
                                                  msg.get("request_id") if msg else None))
            if client.violations >= self.config.max_violations:
                log_event("closed_for_violations", logging.WARNING, conn=client.conn_id, ip=client.ip)
                await client.ws.close(P.CLOSE_TOO_MANY_VIOLATIONS, "too many invalid requests")
                return

    async def _violation(self, client: Client, err: P.ProtocolError, request_id: str | None) -> None:
        if err.violation:
            client.violations += 1
        await client.send(P.error_message(err.code, err.message, request_id, err.extra))

    async def _dispatch(self, client: Client, msg: dict[str, Any]) -> None:
        mtype = msg["type"]
        if mtype == "hello":
            raise P.ProtocolError(P.ALREADY_GREETED, "'hello' was already sent.", violation=True)
        route = self.routes.get(mtype)
        if route is None:
            raise P.ProtocolError(P.UNKNOWN_TYPE, f"Unknown request type '{mtype}'.", violation=True)
        if route.auth == "player" and client.identity is None:
            raise P.ProtocolError(P.NOT_AUTHENTICATED, "Please log in or play as a guest first.")
        if route.limit is not None:
            key = (client.ip if route.scope == "ip" else
                   client.identity.player_id if route.scope == "player" and client.identity else client.conn_id)
            if not route.limit.allow(key):
                raise P.ProtocolError(P.RATE_LIMITED, "Please wait a moment before trying that again.",
                                      violation=True, retry_after=int(route.limit.retry_after(key)) + 1)
        await route.handler(client, msg)

    async def sweep(self) -> int:
        """Closes connections that were greeted but never logged in (resource limit)."""
        now, closed = time.monotonic(), 0
        for client in list(self.registry.clients.values()):
            if client.identity is None and client.greeted and now - client.connected_at > self.config.login_timeout:
                await client.send(P.error_message(P.NOT_AUTHENTICATED, "Closed: no login in time."))
                await client.ws.close(P.CLOSE_LOGIN_TIMEOUT, "login timeout")
                closed += 1
        return closed

    async def _sweep_loop(self) -> None:
        while True:
            await asyncio.sleep(min(30.0, self.config.login_timeout / 2))
            try:
                await self.sweep()
                await self.db.purge_expired_sessions()
            except Exception:
                log.exception("event=sweep_error")

    async def _forget_presence(self, client: Client) -> None:
        player = self.presence.detach(client)
        if player is not None:
            await self.games.player_disconnected(player)

    # ------------------------------------------------------------------ built-in requests
    async def _handle_ping(self, client: Client, msg: dict[str, Any]) -> None:
        await client.send(P.reply(msg, "pong", server_time_ms=int(time.time() * 1000)))

    async def _handle_server_info(self, client: Client, msg: dict[str, Any]) -> None:
        await client.send(P.reply(msg, "server_info",
                                  server_version=__version__,
                                  protocol_version=PROTOCOL_VERSION,
                                  players_online=len(self.registry),
                                  features=self.features()))


def _rid(text: str | bytes) -> str | None:
    """Best effort: the request_id of an invalid message, to address the error."""
    if not isinstance(text, str) or len(text) > 4096:
        return None
    try:
        msg = json.loads(text)
    except (json.JSONDecodeError, RecursionError):
        return None
    rid = msg.get("request_id") if isinstance(msg, dict) else None
    if isinstance(rid, str) and P._REQUEST_ID_RE.match(rid):
        return rid
    return None
