"""Guest login and quick matchmaking."""

from __future__ import annotations

import asyncio

import pytest

from beginnerchess_server import protocol as P
from beginnerchess_server.config import Config

TEN = {"initial_seconds": 600, "increment_seconds": 0}
FIVE = {"initial_seconds": 300, "increment_seconds": 0}


async def guest(open_client, nick: str):
    c = await open_client()
    await c.hello()
    answer = await c.request("login_guest", nickname=nick)
    assert answer["type"] == "logged_in", answer
    return c


async def next_of(c, mtype: str, timeout: float = 5.0) -> dict:
    for i, ev in enumerate(c.events):
        if ev["type"] == mtype:
            return c.events.pop(i)
    while True:
        msg = await c.recv(timeout=timeout)
        if msg["type"] == mtype:
            return msg
        c.events.append(msg)


async def test_guest_login(open_client):
    c = await open_client()
    await c.hello()
    answer = await c.request("login_guest", nickname="Max_123")
    assert answer["player"] == {"name": "Guest_Max_123", "kind": "guest"}
    again = await c.request("login_guest", nickname="Other")
    assert again["code"] == P.CONFLICT


@pytest.mark.parametrize("nick", ["ab", "x" * 17, "with space", "émile", "a-b", "", 42])
async def test_bad_nicknames(open_client, nick):
    c = await open_client()
    await c.hello()
    assert (await c.request("login_guest", nickname=nick))["code"] == P.BAD_MESSAGE


async def test_two_guests_cannot_share_a_name(open_client):
    await guest(open_client, "Max")
    c = await open_client()
    await c.hello()
    assert (await c.request("login_guest", nickname="max"))["code"] == P.CONFLICT     # case-insensitive


async def test_name_is_free_again_after_leaving(open_client, server):
    first = await guest(open_client, "Max")
    await first.ws.close()
    for _ in range(100):
        if not server.lobby.name_in_use("Guest_Max"):
            break
        await asyncio.sleep(0.01)
    await guest(open_client, "Max")


@pytest.mark.parametrize("config", [Config(listen_port=0, guest_access_enabled=False, database_path=":memory:")])
async def test_guests_can_be_switched_off(open_client):
    c = await open_client()
    welcome = await c.hello()
    assert welcome["features"]["guests"] is False
    assert (await c.request("login_guest", nickname="Max"))["code"] == P.UNAVAILABLE


async def test_matchmaking_pairs_two_players(open_client, server):
    a = await guest(open_client, "Alice")
    b = await guest(open_client, "Bob")
    assert (await a.request("matchmaking_join", time_control=TEN))["type"] == "matchmaking_waiting"
    assert (await b.request("matchmaking_join", time_control=TEN))["type"] == "matchmaking_found"
    await next_of(a, "matchmaking_found")
    ga = (await next_of(a, "game_started"))["game"]
    gb = (await next_of(b, "game_started"))["game"]
    assert ga["game_id"] == gb["game_id"]
    assert {ga["your_color"], gb["your_color"]} == {"w", "b"}
    assert ga["time_control"] == TEN and ga["rated"] is False
    assert server.lobby.queue == []
    # Playing players cannot queue again.
    assert (await a.request("matchmaking_join", time_control=TEN))["code"] == P.CONFLICT


async def test_different_time_controls_are_not_paired(open_client, server):
    a = await guest(open_client, "Alice")
    b = await guest(open_client, "Bob")
    await a.request("matchmaking_join", time_control=TEN)
    assert (await b.request("matchmaking_join", time_control=FIVE))["type"] == "matchmaking_waiting"
    assert len(server.lobby.queue) == 2


async def test_duplicate_join_and_cancel(open_client, server):
    a = await guest(open_client, "Alice")
    await a.request("matchmaking_join", time_control=TEN)
    assert (await a.request("matchmaking_join", time_control=TEN))["code"] == P.CONFLICT
    assert (await a.request("matchmaking_cancel"))["type"] == "ok"
    assert server.lobby.queue == []
    assert (await a.request("matchmaking_cancel"))["code"] == P.CONFLICT


async def test_disconnect_leaves_the_queue(open_client, server):
    a = await guest(open_client, "Alice")
    await a.request("matchmaking_join", time_control=TEN)
    await a.ws.close()
    for _ in range(100):
        if not server.lobby.queue:
            break
        await asyncio.sleep(0.01)
    assert server.lobby.queue == []


async def test_guests_cannot_play_rated(open_client):
    a = await guest(open_client, "Alice")
    answer = await a.request("matchmaking_join", time_control=TEN, rated=True)
    assert answer["code"] == P.FORBIDDEN


async def test_matchmaking_needs_login_and_valid_time_control(open_client):
    c = await open_client()
    await c.hello()
    assert (await c.request("matchmaking_join", time_control=TEN))["code"] == P.NOT_AUTHENTICATED
    a = await guest(open_client, "Alice")
    bad = await a.request("matchmaking_join", time_control={"initial_seconds": 1, "increment_seconds": 0})
    assert bad["code"] == P.BAD_MESSAGE


async def test_lobby_list_and_updates(open_client, server):
    a = await guest(open_client, "Alice")
    first = await a.request("lobby_subscribe")
    assert first["type"] == "lobby" and first["total"] == 1
    assert first["players"] == [{"name": "Guest_Alice", "kind": "guest", "status": "available"}]
    b = await guest(open_client, "Bob")
    update = await next_of(a, "lobby")
    assert {p["name"] for p in update["players"]} == {"Guest_Alice", "Guest_Bob"}
    await b.request("matchmaking_join", time_control=TEN)
    update = await next_of(a, "lobby")
    assert {p["name"]: p["status"] for p in update["players"]}["Guest_Bob"] == "waiting"
    await a.request("matchmaking_join", time_control=TEN)              # paired -> both playing
    while True:
        update = await next_of(a, "lobby")
        if all(p["status"] == "playing" for p in update["players"]):
            break
    assert "player_id" not in str(update) and "ip" not in str(update)   # nothing private


async def test_lobby_updates_are_combined(open_client, server):
    a = await guest(open_client, "Alice")
    await a.request("lobby_subscribe")
    for i in range(5):                                                   # five logins at once
        await guest(open_client, f"P{i}xx")
    await asyncio.sleep(1.2)
    updates = [e for e in a.events if e["type"] == "lobby"]
    while True:
        try:
            msg = await a.recv(timeout=0.2)
        except TimeoutError:
            break
        if msg["type"] == "lobby":
            updates.append(msg)
    assert 1 <= len(updates) <= 3 and updates[-1]["total"] == 6


async def test_unsubscribe(open_client, server):
    a = await guest(open_client, "Alice")
    await a.request("lobby_subscribe")
    assert (await a.request("lobby_unsubscribe"))["type"] == "ok"
    await guest(open_client, "Bob")
    with pytest.raises(TimeoutError):
        await next_of(a, "lobby", timeout=1.0)
