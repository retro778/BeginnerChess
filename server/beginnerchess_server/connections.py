"""Connected clients: identity of a connection, rate limiting, connection counts."""

from __future__ import annotations

import ipaddress
import logging
import secrets
import time
from dataclasses import dataclass, field
from typing import Any

from websockets.exceptions import ConnectionClosed

from .protocol import encode

log = logging.getLogger("beginnerchess.connections")


class TokenBucket:
    """Classic token bucket: ``burst`` messages at once, ``rate`` per second sustained."""

    def __init__(self, burst: int, rate: float, clock=time.monotonic):
        self.capacity = float(burst)
        self.rate = float(rate)
        self.tokens = float(burst)
        self.clock = clock
        self.last = clock()

    def allow(self, cost: float = 1.0) -> bool:
        now = self.clock()
        self.tokens = min(self.capacity, self.tokens + (now - self.last) * self.rate)
        self.last = now
        if self.tokens >= cost:
            self.tokens -= cost
            return True
        return False


@dataclass
class Client:
    """One WebSocket connection (not yet a player: see ``identity``)."""

    ws: Any
    ip: str
    bucket: TokenBucket
    conn_id: str = field(default_factory=lambda: secrets.token_hex(8))
    connected_at: float = field(default_factory=time.monotonic)
    greeted: bool = False
    client_name: str = ""
    client_version: str = ""
    violations: int = 0
    #: Set after login (guest or account), e.g. a Player object. None = anonymous.
    identity: Any = None

    async def send(self, msg: dict[str, Any]) -> bool:
        """Sends one message; False if the connection is already gone."""
        try:
            await self.ws.send(encode(msg))
            return True
        except ConnectionClosed:
            return False


def client_ip(remote_address: Any, forwarded_for: str | None, trusted_proxies: list[str]) -> str:
    """The real client address. ``X-Forwarded-For`` is believed only when the
    direct peer is one of our own reverse proxies (otherwise anyone could fake it)."""
    peer = remote_address[0] if isinstance(remote_address, (tuple, list)) and remote_address else "unknown"
    if forwarded_for and peer in trusted_proxies:
        # The right-most entry was added by our proxy; earlier entries are client-controlled.
        candidate = forwarded_for.split(",")[-1].strip()
        try:
            return str(ipaddress.ip_address(candidate))
        except ValueError:
            return peer
    return peer


class ConnectionRegistry:
    """Counts connections overall and per address (limits against floods)."""

    def __init__(self, max_total: int, max_per_ip: int):
        self.max_total = max_total
        self.max_per_ip = max_per_ip
        self.clients: dict[str, Client] = {}
        self.per_ip: dict[str, int] = {}

    def can_accept(self, ip: str) -> str | None:
        """None if a new connection from ``ip`` is allowed, else the reason."""
        if len(self.clients) >= self.max_total:
            return "server full"
        if self.per_ip.get(ip, 0) >= self.max_per_ip:
            return "too many connections from this address"
        return None

    def add(self, client: Client) -> None:
        self.clients[client.conn_id] = client
        self.per_ip[client.ip] = self.per_ip.get(client.ip, 0) + 1

    def remove(self, client: Client) -> None:
        if self.clients.pop(client.conn_id, None) is None:
            return
        left = self.per_ip.get(client.ip, 1) - 1
        if left <= 0:
            self.per_ip.pop(client.ip, None)
        else:
            self.per_ip[client.ip] = left

    def __len__(self) -> int:
        return len(self.clients)
