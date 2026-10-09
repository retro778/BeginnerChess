"""Test fixtures: a real server on a free local port and a small test client."""

from __future__ import annotations

import asyncio
import json
from typing import Any

import pytest
import pytest_asyncio
from websockets.asyncio.client import connect

from beginnerchess_server import PROTOCOL_VERSION
from beginnerchess_server.app import ChessServer
from beginnerchess_server.config import Config


class TestClient:
    """Speaks the protocol like the real client, with helpers for tests."""

    __test__ = False  # not a pytest test class

    def __init__(self, ws):
        self.ws = ws
        self._next = 0

    def rid(self) -> str:
        self._next += 1
        return f"r{self._next}"

    async def send(self, msg: dict[str, Any] | str) -> None:
        await self.ws.send(msg if isinstance(msg, str) else json.dumps(msg))

    async def recv(self, timeout: float = 5.0) -> dict[str, Any]:
        return json.loads(await asyncio.wait_for(self.ws.recv(), timeout))

    async def request(self, mtype: str, **fields: Any) -> dict[str, Any]:
        """Sends a request and returns the answer with the same request_id
        (events that arrive in between are kept in ``events``)."""
        rid = self.rid()
        await self.send({"type": mtype, "request_id": rid, **fields})
        while True:
            msg = await self.recv()
            if msg.get("request_id") == rid:
                return msg
            self.events.append(msg)

    async def hello(self, version: int = PROTOCOL_VERSION) -> dict[str, Any]:
        return await self.request("hello", protocol_version=version,
                                  client_name="BeginnerChess", client_version="2.0.0")

    events: list[dict[str, Any]]


@pytest.fixture
def config() -> Config:
    cfg = Config(listen_port=0, hello_timeout=1.0, heartbeat_interval=5, heartbeat_timeout=5,
                 rate_limit_burst=20, rate_limit_per_second=5, max_connections=50,
                 max_connections_per_ip=50, database_path=":memory:")
    return cfg


@pytest_asyncio.fixture
async def server(config: Config):
    srv = ChessServer(config)
    await srv.start()
    yield srv
    await srv.stop()


@pytest.fixture
def url(server: ChessServer) -> str:
    return f"ws://127.0.0.1:{server.port}{server.config.ws_path}"


@pytest_asyncio.fixture
async def open_client(url: str):
    """Factory: ``c = await open_client()`` gives a connected (not greeted) client."""
    sockets = []

    async def factory(path_url: str | None = None) -> TestClient:
        ws = await connect(path_url or url, compression=None)
        sockets.append(ws)
        client = TestClient(ws)
        client.events = []
        return client

    yield factory
    for ws in sockets:
        await ws.close()
