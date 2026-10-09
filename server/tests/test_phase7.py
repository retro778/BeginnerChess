"""Phase 7: Elo ratings, leaderboard, challenges, rated matchmaking,
disconnection/reconnection, abandonment and server restart recovery."""

from __future__ import annotations

import asyncio

import pytest
from argon2 import PasswordHasher
from websockets.asyncio.client import connect

from beginnerchess_server import lobby as lobby_module
from beginnerchess_server import protocol as P
from beginnerchess_server import ratings as R
from beginnerchess_server.app import ChessServer
from beginnerchess_server.config import Config

PW = "correct horse"
TEN = {"initial_seconds": 600, "increment_seconds": 0}


@pytest.fixture
def config(tmp_path) -> Config:
    return Config(listen_port=0, database_path=str(tmp_path / "p7.db"), max_connections_per_ip=50,
                  rate_limit_burst=500, rate_limit_per_second=500, reconnect_grace_seconds=1)


@pytest.fixture(autouse=True)
def fast_hashing(server):
    server.accounts.hasher = PasswordHasher(time_cost=1, memory_cost=8192, parallelism=1)


async def hello(open_client):
    c = await open_client()
    await c.hello()
    return c


async def account(open_client, name):
    c = await hello(open_client)
    ans = await c.request("register", username=name, password=PW)
    assert ans["type"] == "logged_in", ans
    c.token = ans["session_token"]
    return c


async def guest(open_client, nick):
    c = await hello(open_client)
    ans = await c.request("login_guest", nickname=nick)
    assert ans["type"] == "logged_in", ans
    c.token = ans["session_token"]
    return c


async def next_of(c, mtype, timeout=5.0):
    for i, ev in enumerate(c.events):
        if ev["type"] == mtype:
            return c.events.pop(i)
    while True:
        msg = await c.recv(timeout=timeout)
        if msg["type"] == mtype:
            return msg
        c.events.append(msg)


async def start_by_challenge(a, b, rated=False):
    sent = await a.request("challenge", opponent=b.name, time_control=TEN, rated=rated)
    assert sent["type"] == "challenge_sent", sent
    got = await next_of(b, "challenge_received")
    assert got["challenge"]["from"]["name"] == a.name
    assert (await b.request("challenge_accept", challenge_id=got["challenge"]["challenge_id"]))["type"] == "ok"
    await next_of(a, "challenge_accepted")
    ga = (await next_of(a, "game_started"))["game"]
    gb = (await next_of(b, "game_started"))["game"]
    white, black = (a, b) if ga["your_color"] == "w" else (b, a)
    return ga["game_id"], white, black, gb


async def fools_mate(gid, white, black):
    for who, uci, ply in ((white, "f2f3", 0), (black, "e7e5", 1), (white, "g2g4", 2), (black, "d8h4", 3)):
        assert (await who.request("move", game_id=gid, move=uci, expected_ply=ply))["type"] == "move_accepted"


# --------------------------------------------------------------------------- Elo
def test_elo_formula():
    assert R.expected(1200, 1200) == 0.5
    assert round(R.expected(1600, 1200), 3) == 0.909
    assert R.calc_pair(1200, 1200, 0, 0, 1.0) == (1220, 1180)         # provisional: K = 40
    assert R.calc_pair(1200, 1200, 30, 30, 1.0) == (1210, 1190)       # established: K = 20
    assert R.calc_pair(1200, 1200, 30, 30, 0.5) == (1200, 1200)
    assert R.calc_pair(1500, 1300, 30, 30, 0.5) == (1495, 1305)       # draw favours the lower rated
    assert R.new_rating(110, 110, 0, 0.0) == R.MIN_RATING             # 110 - 20 = 90, but never below 100
    assert R.k_factor(19) == 40 and R.k_factor(20) == 20


# --------------------------------------------------------------------------- rated game, leaderboard
async def test_rated_game_changes_ratings_once(open_client, server):
    a = await account(open_client, "Alice_A")
    b = await account(open_client, "Bobby_B")
    a.name, b.name = "Alice_A", "Bobby_B"
    gid, white, black, _ = await start_by_challenge(a, b, rated=True)
    await fools_mate(gid, white, black)
    for c in (a, b):
        up = await next_of(c, "rating_update")
        assert up["game_id"] == gid
    assert up["white"] == {"before": 1200, "after": 1180, "provisional": True}
    assert up["black"] == {"before": 1200, "after": 1220, "provisional": True}
    # Leaderboard: the winner first.
    board = await a.request("leaderboard")
    assert [(p["rank"], p["name"], p["rating"]) for p in board["players"]] == \
           [(1, black.name, 1220), (2, white.name, 1180)]
    assert board["total"] == 2
    # Rating the same game again does nothing.
    game = server.games.games[gid]
    await server.ratings.on_game_end(game)
    rows = server.db.query_one("SELECT COUNT(*) FROM rating_history")[0]
    assert rows == 2


async def test_casual_and_guest_games_do_not_change_ratings(open_client, server):
    a = await account(open_client, "Alice_A")
    b = await account(open_client, "Bobby_B")
    a.name, b.name = "Alice_A", "Bobby_B"
    gid, white, black, _ = await start_by_challenge(a, b, rated=False)
    await fools_mate(gid, white, black)
    await next_of(a, "game_over")
    await asyncio.sleep(0.2)
    assert server.db.query_one("SELECT COUNT(*) FROM rating_history")[0] == 0
    assert (await a.request("leaderboard"))["total"] == 0


# --------------------------------------------------------------------------- challenges
async def test_challenge_decline_cancel_and_rules(open_client, server):
    a = await guest(open_client, "Alice")
    b = await guest(open_client, "Bobby")
    a.name, b.name = "Guest_Alice", "Guest_Bobby"
    sent = await a.request("challenge", opponent="guest_bobby", time_control=TEN)
    cid = sent["challenge"]["challenge_id"]
    assert sent["challenge"]["expires_seconds"] == 60
    assert (await next_of(b, "challenge_received"))["challenge"]["time_control"] == TEN
    dup = await a.request("challenge", opponent=b.name, time_control=TEN)
    assert dup["code"] == P.CONFLICT                                             # one per opponent
    assert (await a.request("challenge_accept", challenge_id=cid))["code"] == P.FORBIDDEN   # not for a
    assert (await b.request("challenge_decline", challenge_id=cid))["type"] == "ok"
    assert (await next_of(a, "challenge_declined"))["challenge_id"] == cid
    assert (await b.request("challenge_accept", challenge_id=cid))["code"] == P.NOT_FOUND
    sent = await a.request("challenge", opponent=b.name, time_control=TEN)
    assert (await a.request("challenge_cancel", challenge_id=sent["challenge"]["challenge_id"]))["type"] == "ok"
    assert (await next_of(b, "challenge_cancelled"))["reason"] == "cancelled"
    assert (await a.request("challenge", opponent="Guest_Alice", time_control=TEN))["code"] == P.BAD_MESSAGE
    assert (await a.request("challenge", opponent="Nobody", time_control=TEN))["code"] == P.NOT_FOUND
    rated = await a.request("challenge", opponent=b.name, time_control=TEN, rated=True)
    assert rated["code"] == P.FORBIDDEN                                          # guests: casual only


async def test_challenge_expires(open_client, server, monkeypatch):
    monkeypatch.setattr(lobby_module, "CHALLENGE_SECONDS", 0.3)
    a = await guest(open_client, "Alice")
    await guest(open_client, "Bobby")
    await a.request("challenge", opponent="Guest_Bobby", time_control=TEN)
    assert (await next_of(a, "challenge_expired", timeout=3))["challenge_id"]
    assert server.lobby.challenges == {}


async def test_challenge_busy_and_leaving(open_client, server):
    a = await guest(open_client, "Alice")
    b = await guest(open_client, "Bobby")
    c = await guest(open_client, "Carol")
    a.name, b.name = "Guest_Alice", "Guest_Bobby"
    sent = await c.request("challenge", opponent="Guest_Alice", time_control=TEN)
    await next_of(a, "challenge_received")
    await start_by_challenge(a, b)                     # a starts another game ...
    cancelled = await next_of(c, "challenge_cancelled")
    assert cancelled["challenge_id"] == sent["challenge"]["challenge_id"] and cancelled["reason"] == "busy"
    busy = await c.request("challenge", opponent="Guest_Alice", time_control=TEN)
    assert busy["code"] == P.CONFLICT and "playing" in busy["message"]
    # Leaving cancels open challenges.
    d = await guest(open_client, "Dave")
    await c.request("challenge", opponent="Guest_Dave", time_control=TEN)
    await next_of(d, "challenge_received")
    await c.ws.close()
    assert (await next_of(d, "challenge_cancelled"))["reason"] == "left"


async def test_too_many_open_challenges(open_client, server):
    a = await guest(open_client, "Alice")
    for nick in ("Bob1", "Bob2", "Bob3", "Bob4"):
        await guest(open_client, nick)
    for nick in ("Bob1", "Bob2", "Bob3"):
        assert (await a.request("challenge", opponent="Guest_" + nick, time_control=TEN))["type"] == "challenge_sent"
    assert (await a.request("challenge", opponent="Guest_Bob4", time_control=TEN))["code"] == P.CONFLICT


# --------------------------------------------------------------------------- rated matchmaking
async def test_rated_matching_range_grows_while_waiting(open_client, server):
    a = await account(open_client, "Alice_A")
    b = await account(open_client, "Bobby_B")
    server.db.execute_now("UPDATE users SET rating = 1700 WHERE username = 'Bobby_B'")
    for p, _ in server.presence.online.values():
        if p.name == "Bobby_B":
            p.rating = 1700
    assert (await a.request("matchmaking_join", time_control=TEN, rated=True))["type"] == "matchmaking_waiting"
    assert (await b.request("matchmaking_join", time_control=TEN, rated=True))["type"] == "matchmaking_waiting"
    assert await server.lobby.match_waiting() == 0                     # 500 points apart: not yet
    for e in server.lobby.queue:                                       # as if they had waited 30 seconds
        e.since -= 30
    assert await server.lobby.match_waiting() == 1
    assert (await next_of(a, "game_started"))["game"]["rated"] is True


# --------------------------------------------------------------------------- disconnection
async def test_reconnect_to_a_running_game(open_client, server):
    a = await account(open_client, "Alice_A")
    b = await account(open_client, "Bobby_B")
    a.name, b.name = "Alice_A", "Bobby_B"
    gid, white, black, _ = await start_by_challenge(a, b)
    await white.request("move", game_id=gid, move="e2e4", expected_ply=0)
    await white.ws.close()
    note = await next_of(black, "opponent_disconnected")
    assert note["game_id"] == gid and note["grace_seconds"] == 1
    back = await hello(open_client)
    assert (await back.request("resume", session_token=white.token))["type"] == "logged_in"
    snap = (await next_of(back, "game_resumed"))["game"]
    assert snap["moves"] == ["e2e4"] and snap["your_color"] == "w" and snap["status"] == "active"
    await next_of(black, "opponent_reconnected")
    assert (await black.request("move", game_id=gid, move="e7e5", expected_ply=1))["type"] == "move_accepted"
    assert (await next_of(back, "move_accepted"))["move"] == "e7e5"


async def test_guest_can_come_back_and_keeps_the_name(open_client, server):
    a = await guest(open_client, "Alice")
    b = await guest(open_client, "Bobby")
    a.name, b.name = "Guest_Alice", "Guest_Bobby"
    gid, white, black, _ = await start_by_challenge(a, b)
    await a.ws.close()
    await next_of(b, "opponent_disconnected")
    thief = await hello(open_client)
    assert (await thief.request("login_guest", nickname="Alice"))["code"] == P.CONFLICT   # name reserved
    back = await hello(open_client)
    assert (await back.request("resume", session_token=a.token))["type"] == "logged_in"
    assert (await next_of(back, "game_resumed"))["game"]["game_id"] == gid


async def test_abandonment_claim_after_grace(open_client, server):
    a = await guest(open_client, "Alice")
    b = await guest(open_client, "Bobby")
    a.name, b.name = "Guest_Alice", "Guest_Bobby"
    gid, white, black, _ = await start_by_challenge(a, b)
    await white.request("move", game_id=gid, move="e2e4", expected_ply=0)
    await black.request("move", game_id=gid, move="e7e5", expected_ply=1)
    await white.ws.close()
    await next_of(black, "opponent_disconnected")
    early = await black.request("claim_abandonment", game_id=gid, outcome="win")
    assert early["code"] == P.CONFLICT and early["seconds_left"] >= 1
    await asyncio.sleep(1.1)
    over = await black.request("claim_abandonment", game_id=gid, outcome="win")
    assert over["type"] == "game_over" and over["result"] == "0-1" and over["termination"] == "abandoned"


async def test_claim_needs_an_absent_opponent(open_client, server):
    a = await guest(open_client, "Alice")
    b = await guest(open_client, "Bobby")
    a.name, b.name = "Guest_Alice", "Guest_Bobby"
    gid, white, black, _ = await start_by_challenge(a, b)
    r = await black.request("claim_abandonment", game_id=gid, outcome="draw")
    assert r["code"] == P.CONFLICT


# --------------------------------------------------------------------------- restart recovery
async def test_server_restart_restores_account_games(open_client, server, config):
    a = await account(open_client, "Alice_A")
    b = await account(open_client, "Bobby_B")
    g1 = await guest(open_client, "Gus")
    c = await account(open_client, "Cara_C")
    g2 = await guest(open_client, "Gwen")
    g3 = await guest(open_client, "Gil")
    a.name, b.name, g1.name, c.name = "Alice_A", "Bobby_B", "Guest_Gus", "Cara_C"
    g2.name, g3.name = "Guest_Gwen", "Guest_Gil"
    gid, white, black, _ = await start_by_challenge(a, b)
    await white.request("move", game_id=gid, move="d2d4", expected_ply=0)
    await black.request("move", game_id=gid, move="d7d5", expected_ply=1)
    await white.request("move", game_id=gid, move="c2c4", expected_ply=2)
    ggid, gw, gb, _ = await start_by_challenge(g1, c)
    await gw.request("move", game_id=ggid, move="e2e4", expected_ply=0)
    await gb.request("move", game_id=ggid, move="e7e5", expected_ply=1)
    pgid, pw, pb, _ = await start_by_challenge(g2, g3)                  # two guests: never stored
    await pw.request("move", game_id=pgid, move="g1f3", expected_ply=0)
    await pb.request("move", game_id=pgid, move="g8f6", expected_ply=1)
    assert server.db.query_one("SELECT COUNT(*) FROM games WHERE id = ?", pgid)[0] == 0
    row = server.db.query_one("SELECT status, moves FROM games WHERE id = ?", gid)
    assert tuple(row) == ("active", "d2d4 d7d5 c2c4")                   # saved after every move
    await server.stop()

    second = ChessServer(config)                                          # same database file
    second.accounts.hasher = PasswordHasher(time_cost=1, memory_cost=8192, parallelism=1)
    await second.start()
    try:
        assert gid in second.games.games and second.games.games[gid].ply == 3
        cancelled = second.db.query_one("SELECT status, result, termination FROM games WHERE id = ?", ggid)
        assert tuple(cancelled) == ("aborted", None, "server_restart")    # with a guest: no result, no winner
        assert pgid not in second.games.games
        url = f"ws://127.0.0.1:{second.port}{config.ws_path}"
        import json
        async with connect(url) as ws:
            await ws.send(json.dumps({"type": "hello", "protocol_version": 1, "client_name": "t",
                                      "client_version": "1"}))
            await ws.recv()
            await ws.send(json.dumps({"type": "resume", "session_token": black.token}))
            msgs = [json.loads(await ws.recv()) for _ in range(2)]
            resumed = next(m for m in msgs if m["type"] == "game_resumed")["game"]
            assert resumed["moves"] == ["d2d4", "d7d5", "c2c4"] and resumed["turn"] == "b"
            assert resumed["clock"]["white_ms"] <= 600_000 and resumed["status"] == "active"
            assert resumed["away"].get("w") is not None                     # white not back yet
    finally:
        await second.stop()
