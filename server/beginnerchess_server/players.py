"""Who is playing: identities (guests and accounts) and where to reach them.

A ``Player`` is the identity behind a connection; ``Presence`` maps each
player to the connection currently used, so that events reach the player even
after a reconnect (the old connection is replaced).
"""

from __future__ import annotations

import secrets
from dataclasses import dataclass, field
from typing import Any

from .connections import Client


@dataclass(eq=False)
class Player:
    player_id: str                      # internal, never chosen by the client
    name: str                           # display name ("Guest_Max" for guests)
    kind: str                           # "guest" or "account"
    rating: int | None = None           # online Elo (accounts only)
    provisional: bool = True
    account_id: int | None = None       # database id for accounts
    session: Any = None                 # session record (accounts), set by auth

    @property
    def is_guest(self) -> bool:
        return self.kind == "guest"

    def public(self) -> dict[str, Any]:
        """What other players may see (never ids, tokens or addresses)."""
        info: dict[str, Any] = {"name": self.name, "kind": self.kind}
        if self.rating is not None:
            info["rating"] = self.rating
            info["provisional"] = self.provisional
        return info


def new_guest_id() -> str:
    return "g-" + secrets.token_hex(8)


@dataclass
class Presence:
    """player_id -> current connection."""

    online: dict[str, tuple[Player, Client]] = field(default_factory=dict)

    def attach(self, player: Player, client: Client) -> Client | None:
        """Binds ``player`` to ``client``; returns the replaced connection, if any."""
        old = self.online.get(player.player_id)
        self.online[player.player_id] = (player, client)
        client.identity = player
        return old[1] if old and old[1] is not client else None

    def detach(self, client: Client) -> Player | None:
        """Called when ``client`` disconnects; the player is offline unless
        another connection already replaced this one."""
        player = client.identity
        if player is None:
            return None
        current = self.online.get(player.player_id)
        if current and current[1] is client:
            del self.online[player.player_id]
            return player
        return None

    def client_of(self, player: Player) -> Client | None:
        entry = self.online.get(player.player_id)
        return entry[1] if entry else None

    def is_online(self, player: Player) -> bool:
        return player.player_id in self.online

    async def send(self, player: Player, msg: dict[str, Any]) -> bool:
        client = self.client_of(player)
        return await client.send(msg) if client else False

    def __len__(self) -> int:
        return len(self.online)
