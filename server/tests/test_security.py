"""Phase 8: limits, abuse protection, manipulation attempts, secret-free logs,
and the administration interface."""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sqlite3
import stat

import pytest
from argon2 import PasswordHasher
from websockets.asyncio.client import connect
from websockets.exceptions import InvalidStatus

from beginnerchess_server import admin as admin_cli
from beginnerchess_server import protocol as P
from beginnerchess_server.config import Config
from beginnerchess_server.limits import SlidingWindow

PW = "correct horse"
TEN = {"initial_seconds": 600, "increment_seconds": 0}


@pytest.fixture
def config(tmp_path) -> Config:
    return Config(listen_port=0, database_path=str(tmp_path / "s.db"), max_connections_per_ip=50,
                  rate_limit_burst=500, rate_limit_per_second=500, new_connections_per_minute=500,
                  admin_socket=str(tmp_path / "admin.sock"))


@pytest.fixture(autouse=True)
def fast_hashing(server):
    server.accounts.hasher = PasswordHasher(time_cost=1, memory_cost=8192, parallelism=1)


async def hello(open_client):
    c = await open_client()
    await c.hello()
    return c


async def register(open_client, name):
    c = await hello(open_client)
    ans = await c.request("register", username=name, password=PW)
    assert ans["type"] == "logged_in", ans
    c.token = ans["session_token"]
    return c


async def admin(server, **request):
    return await asyncio.to_thread(admin_cli.send, server.config.admin_socket, request)


# --------------------------------------------------------------------------- limits
def test_sliding_window():
    now = [0.0]
    w = SlidingWindow(2, 10, clock=lambda: now[0])
    assert w.allow("a") and w.allow("a") and not w.allow("a") and w.allow("b")
    assert 9.9 < w.retry_after("a") <= 10
    now[0] = 10.0
    assert w.allow("a")
    small = SlidingWindow(1, 10, clock=lambda: now[0], max_keys=3)
    for k in "abcdef":
        small.allow(k)
    assert len(small.events) <= 3                          # memory stays bounded


@pytest.mark.parametrize("config", [Config(listen_port=0, database_path=":memory:", registrations_per_hour=2,
                                           max_connections_per_ip=50, new_connections_per_minute=500)])
async def test_registrations_per_address(open_client):
    for i in range(2):
        await register(open_client, f"User_{i}")
    c = await hello(open_client)
    assert (await c.request("register", username="User_9", password=PW))["code"] == P.RATE_LIMITED


@pytest.mark.parametrize("config", [Config(listen_port=0, database_path=":memory:", challenges_per_minute=2,
                                           matchmaking_per_minute=2, max_connections_per_ip=50,
                                           new_connections_per_minute=500)])
async def test_challenge_and_matchmaking_spam(open_client):
    a = await hello(open_client)
    await a.request("login_guest", nickname="Spammer")
    for nick in ("T1x", "T2x", "T3x"):
        t = await hello(open_client)
        await t.request("login_guest", nickname=nick)
    assert (await a.request("challenge", opponent="Guest_T1x", time_control=TEN))["type"] == "challenge_sent"
    assert (await a.request("challenge", opponent="Guest_T2x", time_control=TEN))["type"] == "challenge_sent"
    third = await a.request("challenge", opponent="Guest_T3x", time_control=TEN)
    assert third["code"] == P.RATE_LIMITED and third["retry_after"] >= 1
    for _ in range(2):
        await a.request("matchmaking_join", time_control=TEN)
        await a.request("matchmaking_cancel")
    assert (await a.request("matchmaking_join", time_control=TEN))["code"] == P.RATE_LIMITED


@pytest.mark.parametrize("config", [Config(listen_port=0, database_path=":memory:", new_connections_per_minute=3,
                                           max_connections_per_ip=50)])
async def test_connection_flood_is_refused(open_client):
    for _ in range(3):
        await open_client()
    with pytest.raises(InvalidStatus) as info:
        await open_client()
    assert info.value.response.status_code == 503


@pytest.mark.parametrize("config", [Config(listen_port=0, database_path=":memory:", login_timeout=0.2)])
async def test_idle_connections_without_login_are_closed(open_client, server):
    idle = await hello(open_client)
    player = await hello(open_client)
    await player.request("login_guest", nickname="Active")
    await asyncio.sleep(0.3)
    await server.sweep()                       # (the background sweeper may already have done it)
    msg = await idle.recv()
    assert msg["code"] == P.NOT_AUTHENTICATED
    with pytest.raises(Exception):
        await idle.recv(timeout=2)
    assert idle.ws.close_code == P.CLOSE_LOGIN_TIMEOUT
    assert (await player.request("ping"))["type"] == "pong"           # logged-in players stay


async def test_session_cap(open_client, server):
    c = await register(open_client, "Maya_7")
    await c.request("logout")
    for _ in range(12):
        x = await hello(open_client)
        assert (await x.request("login", username="Maya_7", password=PW))["type"] == "logged_in"
        await x.ws.close()
    await asyncio.sleep(0.1)
    assert server.db.query_one("SELECT COUNT(*) FROM sessions")[0] == server.config.sessions_per_user


async def test_token_guessing_is_limited(open_client):
    c = await hello(open_client)
    codes = [(await c.request("resume", session_token="x" * 40 + str(i)))["code"] for i in range(22)]
    assert codes[0] == P.NOT_AUTHENTICATED and codes[-1] == P.RATE_LIMITED


# --------------------------------------------------------------------------- manipulation attempts
async def test_clients_cannot_send_server_messages(open_client):
    c = await hello(open_client)
    await c.request("login_guest", nickname="Mallory")
    for fake in ("rating_update", "game_over", "move_accepted", "game_started", "logged_in", "welcome"):
        assert (await c.request(fake, result="1-0", rating=3000))["code"] == P.UNKNOWN_TYPE


async def test_extra_fields_are_ignored(open_client, server):
    c = await hello(open_client)
    ans = await c.request("register", username="Mallory", password=PW, rating=3000, status="active", id=1)
    assert ans["player"]["rating"] == 1200
    w = await hello(open_client)
    await w.request("login_guest", nickname="Whitey")
    b = await hello(open_client)
    await b.request("login_guest", nickname="Blacky")
    game = await server.games.create_game(*[p for p, _ in list(server.presence.online.values())[-2:]],
                                          __import__("beginnerchess_server.games", fromlist=["TimeControl"]).TimeControl(600_000, 0),
                                          rated=False)
    white_client = w if game.white.name == "Guest_Whitey" else b
    black_client = b if white_client is w else w
    for x in (white_client, black_client):
        await x.recv()                                                # game_started
    r = await white_client.request("move", game_id=game.game_id, move="e2e4", expected_ply=0,
                                   white_ms=99_999_999, clock={"white_ms": 99_999_999}, result="1-0")
    assert r["type"] == "move_accepted" and r["clock"]["white_ms"] == 600_000
    assert game.status == "active" and game.result is None
    # Ending the game twice is impossible; the second request finds a finished game.
    first = await black_client.request("resign", game_id=game.game_id)
    second = await black_client.request("resign", game_id=game.game_id)
    assert first["type"] == "game_over" and second["code"] == P.GAME_OVER


def test_library_debug_logging_stays_off():
    """The websockets library logs frame contents at DEBUG; the server keeps it
    at WARNING even when the operator chooses log_level DEBUG."""
    from beginnerchess_server.main import setup_logging
    setup_logging("DEBUG")
    assert logging.getLogger("websockets").getEffectiveLevel() >= logging.WARNING
    assert logging.getLogger("beginnerchess").getEffectiveLevel() <= logging.DEBUG


async def test_logs_contain_no_secrets(open_client, caplog):
    logging.getLogger("websockets").setLevel(logging.WARNING)     # as in production (main.setup_logging)
    caplog.set_level(logging.DEBUG, logger="beginnerchess")       # everything of our own code
    c = await register(open_client, "Secretive")
    await c.request("logout")
    x = await hello(open_client)
    await x.request("login", username="Secretive", password="wrong password!")
    ok = await x.request("login", username="Secretive", password=PW)
    y = await hello(open_client)
    await y.request("resume", session_token=ok["session_token"])
    text = caplog.text
    assert PW not in text and "wrong password!" not in text
    assert c.token not in text and ok["session_token"] not in text
    assert "event=login" in text and "event=registered" in text            # but the events are logged


# --------------------------------------------------------------------------- administration
async def test_admin_socket_permissions_and_status(open_client, server):
    mode = stat.S_IMODE(os.stat(server.config.admin_socket).st_mode)
    assert mode == 0o660
    await register(open_client, "Maya_7")
    st = await admin(server, cmd="status")
    assert st["ok"] and st["players_online"] == 1 and st["database"]["users"] == 1
    assert st["database"]["schema_version"] >= 2 and st["active_games"] == 0
    logging.getLogger("beginnerchess.test").error("something broke")
    assert (await admin(server, cmd="status"))["errors_logged"] >= 1
    assert (await admin(server, cmd="nonsense"))["ok"] is False


async def test_admin_suspend_kick_unsuspend(open_client, server):
    c = await register(open_client, "Rude_1")
    res = await admin(server, cmd="suspend", user="rude_1")
    assert res["ok"] and res["connection_closed"] is True and res["sessions_ended"] == 1
    note = await c.recv()
    assert note["type"] == "server_notice"
    with pytest.raises(Exception):
        await c.recv(timeout=2)
    assert c.ws.close_code == P.CLOSE_ADMIN
    x = await hello(open_client)
    assert (await x.request("login", username="Rude_1", password=PW))["message"] == "This account is suspended."
    assert (await x.request("resume", session_token=c.token))["code"] == P.NOT_AUTHENTICATED
    assert (await admin(server, cmd="unsuspend", user="Rude_1"))["ok"]
    assert (await x.request("login", username="Rude_1", password=PW))["type"] == "logged_in"
    assert (await admin(server, cmd="kick", user="Rude_1"))["connection_closed"] is True
    assert (await admin(server, cmd="suspend", user="Nobody"))["ok"] is False


async def test_admin_switches_features(open_client, server):
    assert (await admin(server, cmd="set", feature="registration", value=False))["ok"]
    c = await hello(open_client)
    assert (await c.request("register", username="Late_1", password=PW))["code"] == P.UNAVAILABLE
    assert (await admin(server, cmd="set", feature="guests", value=False))["features"]["guests"] is False
    assert (await c.request("login_guest", nickname="Late"))["code"] == P.UNAVAILABLE
    assert (await admin(server, cmd="set", feature="rated_games", value=False))["features"]["rated_games"] is False
    assert (await admin(server, cmd="set", feature="color", value=True))["ok"] is False


async def test_backups_online_and_offline(open_client, server, tmp_path):
    await register(open_client, "Maya_7")
    target = str(tmp_path / "backup.db")
    res = await admin(server, cmd="backup", path=target)
    assert res["ok"] and res["integrity_check"] == "ok"
    copy = sqlite3.connect(target)
    assert copy.execute("SELECT username FROM users").fetchone()[0] == "Maya_7"
    copy.close()
    offline = str(tmp_path / "offline.db")
    rc = await asyncio.to_thread(admin_cli.main, ["--database", server.config.database_path, "backup", offline])
    assert rc == 0 and os.path.getsize(offline) > 0
    assert (await admin(server, cmd="integrity"))["integrity_check"] == "ok"
