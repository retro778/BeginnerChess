"""Phase 2: transport, handshake, protocol errors, limits, health endpoint."""

from __future__ import annotations

import asyncio
import json
import urllib.request

import pytest
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed, InvalidStatus

from beginnerchess_server import protocol as P
from beginnerchess_server.config import Config, ConfigError, load_config
from beginnerchess_server.connections import TokenBucket, client_ip


async def closed_code(client, timeout: float = 5.0) -> int | None:
    """Waits until the server closes the connection; returns the close code."""
    try:
        while True:
            await asyncio.wait_for(client.ws.recv(), timeout)
    except ConnectionClosed as exc:
        return exc.rcvd.code if exc.rcvd else None


# --------------------------------------------------------------------------- handshake
async def test_hello_welcome(open_client):
    c = await open_client()
    msg = await c.hello()
    assert msg["type"] == "welcome"
    assert msg["protocol_version"] == 1
    assert msg["limits"]["max_message_size"] == 16384
    assert set(msg["features"]) == {"guests", "registration", "rated_games"}
    assert msg["connection_id"]


async def test_incompatible_version_is_rejected_politely(open_client):
    c = await open_client()
    msg = await c.hello(version=99)
    assert msg["type"] == "error" and msg["code"] == P.INCOMPATIBLE_VERSION
    assert "update BeginnerChess" in msg["message"]
    assert await closed_code(c) == P.CLOSE_INCOMPATIBLE


async def test_first_message_must_be_hello(open_client):
    c = await open_client()
    msg = await c.request("ping")
    assert msg["code"] == P.HELLO_REQUIRED
    assert await closed_code(c) == 1008


async def test_hello_timeout(open_client):
    c = await open_client()
    msg = await c.recv(timeout=3)
    assert msg["code"] == P.HELLO_REQUIRED
    assert await closed_code(c) == P.CLOSE_HELLO_TIMEOUT


async def test_second_hello_is_an_error(open_client):
    c = await open_client()
    await c.hello()
    msg = await c.hello()
    assert msg["code"] == P.ALREADY_GREETED


# --------------------------------------------------------------------------- requests
async def test_ping_and_server_info(open_client):
    c = await open_client()
    await c.hello()
    pong = await c.request("ping")
    assert pong["type"] == "pong" and isinstance(pong["server_time_ms"], int)
    info = await c.request("server_info")
    assert info["type"] == "server_info" and info["players_online"] >= 1


async def test_request_id_is_echoed(open_client):
    c = await open_client()
    await c.hello()
    await c.send({"type": "ping", "request_id": "abc-123"})
    assert (await c.recv())["request_id"] == "abc-123"


@pytest.mark.parametrize("raw, code", [
    ("{not json", P.BAD_JSON),
    ("[1, 2, 3]", P.BAD_MESSAGE),
    ('{"no_type": 1}', P.BAD_MESSAGE),
    ('{"type": "Ping"}', P.BAD_MESSAGE),
    ('{"type": "ping", "request_id": "has spaces"}', P.BAD_MESSAGE),
    ('{"type": "ping", "request_id": 5}', P.BAD_MESSAGE),
    ('{"type": "no_such_request"}', P.UNKNOWN_TYPE),
    ('{"type": "ping", "x": [[[[[[[[[[1]]]]]]]]]]}', P.BAD_MESSAGE),
])
async def test_malformed_messages_get_errors(open_client, raw, code):
    c = await open_client()
    await c.hello()
    await c.send(raw)
    msg = await c.recv()
    assert msg["type"] == "error" and msg["code"] == code
    # The connection stays usable after one bad message.
    assert (await c.request("ping"))["type"] == "pong"


async def test_error_keeps_valid_request_id(open_client):
    c = await open_client()
    await c.hello()
    await c.send('{"type": "nonsense_type", "request_id": "q7"}')
    msg = await c.recv()
    assert msg["code"] == P.UNKNOWN_TYPE and msg["request_id"] == "q7"


async def test_binary_frames_are_rejected(open_client):
    c = await open_client()
    await c.hello()
    await c.ws.send(b"\x00\x01")
    assert (await c.recv())["code"] == P.BAD_MESSAGE


async def test_oversized_message_closes_connection(open_client):
    c = await open_client()
    await c.hello()
    await c.send(json.dumps({"type": "ping", "pad": "x" * 20000}))
    assert await closed_code(c) == 1009          # "message too big"


async def test_too_many_violations_close_the_connection(open_client, server):
    c = await open_client()
    await c.hello()
    for _ in range(server.config.max_violations):
        await c.send("garbage")
    assert await closed_code(c) == P.CLOSE_TOO_MANY_VIOLATIONS


async def test_rate_limit(open_client, server):
    c = await open_client()
    await c.hello()
    for i in range(40):                            # burst is 20
        await c.send({"type": "ping", "request_id": f"p{i}"})
    answers = []
    try:
        while len(answers) < 40:
            answers.append(await c.recv(timeout=2))
    except (TimeoutError, ConnectionClosed):
        pass
    assert any(a.get("code") == P.RATE_LIMITED for a in answers)
    assert sum(1 for a in answers if a["type"] == "pong") >= 20


async def test_requests_needing_login_are_refused(open_client, server):
    async def secret(client, msg):
        await client.send(P.reply(msg, "secret"))
    server.route("test_secret", secret, auth="player")
    c = await open_client()
    await c.hello()
    msg = await c.request("test_secret")
    assert msg["code"] == P.NOT_AUTHENTICATED


# --------------------------------------------------------------------------- HTTP side
async def test_wrong_path_is_404(server):
    with pytest.raises(InvalidStatus) as info:
        await connect(f"ws://127.0.0.1:{server.port}/other")
    assert info.value.response.status_code == 404


async def test_health_endpoint(server):
    def fetch():
        with urllib.request.urlopen(f"http://127.0.0.1:{server.port}/chess/health", timeout=5) as r:
            return r.status, json.loads(r.read())
    status, body = await asyncio.to_thread(fetch)
    assert status == 200 and body["status"] == "ok" and body["protocol_version"] == 1
    assert "players" not in json.dumps(body)       # nothing private or operational


@pytest.mark.parametrize("config", [Config(listen_port=0, max_connections=50, max_connections_per_ip=2,
                                           database_path=":memory:")])
async def test_connection_limit_per_ip(open_client):
    await open_client()
    await open_client()
    with pytest.raises(InvalidStatus) as info:
        await open_client()
    assert info.value.response.status_code == 503


async def test_graceful_shutdown_notifies_clients(open_client, server):
    c = await open_client()
    await c.hello()
    await server.stop()
    msg = await c.recv()
    assert msg["type"] == "server_shutdown"
    assert await closed_code(c) == 1001


async def test_disconnect_is_cleaned_up(open_client, server):
    c = await open_client()
    await c.hello()
    assert len(server.registry) == 1
    await c.ws.close()
    for _ in range(50):
        if len(server.registry) == 0:
            break
        await asyncio.sleep(0.02)
    assert len(server.registry) == 0 and server.registry.per_ip == {}


# --------------------------------------------------------------------------- units
def test_token_bucket():
    now = [0.0]
    bucket = TokenBucket(burst=3, rate=1.0, clock=lambda: now[0])
    assert [bucket.allow() for _ in range(4)] == [True, True, True, False]
    now[0] += 1.0
    assert bucket.allow() and not bucket.allow()


def test_forwarded_for_only_from_trusted_proxy():
    trusted = ["127.0.0.1"]
    assert client_ip(("127.0.0.1", 5), "1.2.3.4", trusted) == "1.2.3.4"
    assert client_ip(("127.0.0.1", 5), "6.6.6.6, 1.2.3.4", trusted) == "1.2.3.4"
    assert client_ip(("9.9.9.9", 5), "1.2.3.4", trusted) == "9.9.9.9"      # spoof attempt
    assert client_ip(("127.0.0.1", 5), "not-an-ip", trusted) == "127.0.0.1"


def test_config_file_and_environment(tmp_path):
    f = tmp_path / "c.toml"
    f.write_text('[server]\nlisten_port = 9000\nregistration_enabled = false\n'
                 'trusted_proxies = ["10.0.0.1"]\n')
    cfg = load_config(f, environ={"BCS_MAX_CONNECTIONS": "77", "BCS_RATED_GAMES_ENABLED": "no"})
    assert cfg.listen_port == 9000 and not cfg.registration_enabled
    assert cfg.trusted_proxies == ["10.0.0.1"]
    assert cfg.max_connections == 77 and not cfg.rated_games_enabled
    assert cfg.listen_host == "127.0.0.1"           # safe default: never public


@pytest.mark.parametrize("text", ["unknown_key = 1\n", "listen_port = 'abc'\n",
                                  "listen_port = 70000\n", "max_message_size = 0\n",
                                  "ws_path = 'chess'\n", "registration_enabled = 3\n"])
def test_bad_config_is_rejected(tmp_path, text):
    f = tmp_path / "c.toml"
    f.write_text(text)
    with pytest.raises(ConfigError):
        load_config(f, environ={})


def test_example_config_is_valid():
    from pathlib import Path
    example = Path(__file__).resolve().parent.parent / "config.example.toml"
    cfg = load_config(example, environ={})
    assert cfg.listen_host == "127.0.0.1" and cfg.listen_port == 8765


def test_production_config_is_valid():
    from pathlib import Path
    prod = Path(__file__).resolve().parent.parent / "deployment" / "server.toml"
    cfg = load_config(prod, environ={})
    assert cfg.listen_host == "127.0.0.1" and cfg.listen_port == 8765
    assert cfg.database_path.startswith("/var/lib/beginnerchess/")
    assert cfg.admin_socket.startswith("/run/beginnerchess/")
