"""Accounts: registration, login, sessions, profiles, history, deletion, storage."""

from __future__ import annotations

import asyncio
import sqlite3

import pytest
from argon2 import PasswordHasher

from beginnerchess_server import protocol as P
from beginnerchess_server.config import Config
from beginnerchess_server.games import TimeControl
from beginnerchess_server.persistence import MIGRATIONS_DIR, Database, _split_sql, token_hash

PW = "correct horse"


@pytest.fixture
def config(tmp_path) -> Config:
    return Config(listen_port=0, database_path=str(tmp_path / "test.db"), max_connections_per_ip=50,
                  rate_limit_burst=200, rate_limit_per_second=200)


@pytest.fixture(autouse=True)
def fast_hashing(server):
    # Still Argon2id, with cheaper parameters so that the tests run quickly.
    server.accounts.hasher = PasswordHasher(time_cost=1, memory_cost=8192, parallelism=1)


async def connected(open_client):
    c = await open_client()
    await c.hello()
    return c


async def register(open_client, name="Maya_7", pw=PW):
    c = await connected(open_client)
    answer = await c.request("register", username=name, password=pw)
    assert answer["type"] == "logged_in", answer
    return c, answer


async def wait_type(c, mtype, timeout=5.0):
    for i, ev in enumerate(c.events):
        if ev["type"] == mtype:
            return c.events.pop(i)
    while True:
        msg = await c.recv(timeout=timeout)
        if msg["type"] == mtype:
            return msg
        c.events.append(msg)


# --------------------------------------------------------------------------- registration
async def test_register(open_client, server):
    c, answer = await register(open_client)
    assert answer["player"] == {"name": "Maya_7", "kind": "account", "rating": 1200, "provisional": True}
    assert len(answer["session_token"]) >= 40
    row = server.db.query_one("SELECT password_hash FROM users WHERE username = 'Maya_7'")
    assert row[0].startswith("$argon2id$") and PW not in row[0]          # never stored as text
    stored = server.db.query_one("SELECT token_hash FROM sessions")[0]
    assert stored == token_hash(answer["session_token"])                  # only the hash is kept


@pytest.mark.parametrize("name, pw, why", [
    ("ab", PW, "3-16"), ("way_too_long_name_x", PW, "3-16"), ("with space", PW, "3-16"),
    ("Guest_Max", PW, "Guest"), ("guesthouse", PW, "Guest"),
    ("Maya", "short", "8-128"), ("Maya", "x" * 129, "8-128"), ("Maya1234", "maya1234", "different"),
])
async def test_invalid_registrations(open_client, name, pw, why):
    c = await connected(open_client)
    answer = await c.request("register", username=name, password=pw)
    assert answer["code"] == P.BAD_MESSAGE and why in answer["message"]


async def test_duplicate_name_any_case(open_client):
    await register(open_client, "Maya_7")
    c = await connected(open_client)
    assert (await c.request("register", username="maya_7", password=PW))["code"] == P.CONFLICT


@pytest.mark.parametrize("config", [Config(listen_port=0, registration_enabled=False, database_path=":memory:")])
async def test_registration_can_be_switched_off(open_client):
    c = await connected(open_client)
    assert (await c.request("register", username="Maya", password=PW))["code"] == P.UNAVAILABLE


# --------------------------------------------------------------------------- login / sessions
async def test_login_and_wrong_password(open_client, server):
    first, _ = await register(open_client)
    await first.request("logout")
    c = await connected(open_client)
    bad = await c.request("login", username="Maya_7", password="wrong password")
    nobody = await c.request("login", username="Nobody", password="wrong password")
    assert bad["code"] == nobody["code"] == P.FORBIDDEN
    assert bad["message"] == nobody["message"] == "Wrong user name or password."   # no hint which one
    ok = await c.request("login", username="MAYA_7", password=PW)                  # name in any case
    assert ok["type"] == "logged_in" and ok["player"]["name"] == "Maya_7"


async def test_login_throttling(open_client):
    first, _ = await register(open_client)
    await first.request("logout")
    c = await connected(open_client)
    for _ in range(5):
        assert (await c.request("login", username="Maya_7", password="nope nope"))["code"] == P.FORBIDDEN
    blocked = await c.request("login", username="Maya_7", password=PW)              # even the right one
    assert blocked["code"] == P.RATE_LIMITED


async def test_resume_with_token(open_client):
    first, answer = await register(open_client)
    token = answer["session_token"]
    await first.ws.close()
    c = await connected(open_client)
    resumed = await c.request("resume", session_token=token)
    assert resumed["type"] == "logged_in" and resumed["player"]["name"] == "Maya_7"
    bad = await (await connected(open_client)).request("resume", session_token="x" * 43)
    assert bad["code"] == P.NOT_AUTHENTICATED


async def test_logout_revokes_the_session(open_client, server):
    c, answer = await register(open_client)
    assert (await c.request("logout"))["type"] == "logged_out"
    assert (await c.request("matchmaking_cancel"))["code"] == P.NOT_AUTHENTICATED   # no longer logged in
    again = await (await connected(open_client)).request("resume", session_token=answer["session_token"])
    assert again["code"] == P.NOT_AUTHENTICATED


async def test_expired_session(open_client, server):
    c, answer = await register(open_client)
    await c.ws.close()
    server.db.execute_now("UPDATE sessions SET expires_at = '2000-01-01T00:00:00+00:00'")
    r = await (await connected(open_client)).request("resume", session_token=answer["session_token"])
    assert r["code"] == P.NOT_AUTHENTICATED
    assert server.db.query_one("SELECT COUNT(*) FROM sessions")[0] == 0


async def test_second_login_replaces_the_first(open_client):
    first, _ = await register(open_client)
    second = await connected(open_client)
    assert (await second.request("login", username="Maya_7", password=PW))["type"] == "logged_in"
    note = await wait_type(first, "session_replaced")
    assert "another place" in note["message"]
    with pytest.raises(Exception):
        while True:
            await first.recv(timeout=2)
    assert first.ws.close_code == P.CLOSE_SESSION_REPLACED


async def test_suspended_account(open_client, server):
    first, _ = await register(open_client)
    await first.request("logout")
    await server.db.set_status("Maya_7", "suspended")
    c = await connected(open_client)
    assert (await c.request("login", username="Maya_7", password=PW))["message"] == "This account is suspended."


# --------------------------------------------------------------------------- games, profile, history
async def play_short_game(server, a, b):
    """a (white) and b play fool's mate; returns the game id."""
    game = await server.games.create_game(a.player, b.player, TimeControl(600_000, 0), rated=False)
    for who, uci, ply in ((a, "f2f3", 0), (b, "e7e5", 1), (a, "g2g4", 2), (b, "d8h4", 3)):
        assert (await who.request("move", game_id=game.game_id, move=uci, expected_ply=ply))["type"] == "move_accepted"
    await wait_type(a, "game_over")
    return game.game_id


async def players(server, *clients):
    for c, name in clients:
        c.player = next(p for p, cl in server.presence.online.values() if p.name == name)


async def test_games_are_stored_and_listed(open_client, server):
    a, _ = await register(open_client, "Alice_A")
    b, _ = await register(open_client, "Bobby_B")
    await players(server, (a, "Alice_A"), (b, "Bobby_B"))
    gid = await play_short_game(server, a, b)
    for _ in range(50):                                   # stored by the game-end callback
        if server.db.query_one("SELECT COUNT(*) FROM games WHERE status != 'active'")[0]:
            break
        await asyncio.sleep(0.02)
    prof = (await b.request("profile"))["profile"]
    assert (prof["games"], prof["wins"], prof["losses"], prof["draws"]) == (1, 1, 0, 0)
    assert prof["recent_games"][0]["outcome"] == "win" and prof["recent_games"][0]["opponent"] == "Alice_A"
    other = (await b.request("profile", username="alice_a"))["profile"]
    assert other["name"] == "Alice_A" and other["losses"] == 1
    hist = await a.request("history")
    assert len(hist["games"]) == 1 and hist["games"][0]["outcome"] == "loss" and hist["games"][0]["color"] == "w"
    rec = (await a.request("game_record", game_id=gid))["game"]
    assert rec["moves"] == ["f2f3", "e7e5", "g2g4", "d8h4"] and "Qh4#" in rec["pgn"]
    assert rec["result"] == "0-1" and rec["termination"] == "checkmate"
    assert (await a.request("game_record", game_id="nope"))["code"] == P.NOT_FOUND
    assert (await a.request("profile", username="Nobody"))["code"] == P.NOT_FOUND
    text = str(prof) + str(rec)
    assert "password" not in text and "token" not in text and "127.0.0.1" not in text


def count_games(server) -> int:
    return server.db.query_one("SELECT COUNT(*) FROM games")[0]


def game_status(server, gid):
    row = server.db.query_one("SELECT status FROM games WHERE id = ?", gid)
    return row[0] if row else None


async def test_only_games_with_an_account_are_stored(open_client, server):
    g1 = await connected(open_client)
    await g1.request("login_guest", nickname="Visitor")
    g2 = await connected(open_client)
    await g2.request("login_guest", nickname="Tourist")
    assert (await g1.request("history"))["code"] == P.FORBIDDEN
    assert (await g1.request("profile"))["code"] == P.FORBIDDEN
    await players(server, (g1, "Guest_Visitor"), (g2, "Guest_Tourist"))
    await play_short_game(server, g1, g2)                          # two guests: nobody's history
    await wait_type(g2, "game_over")
    await asyncio.sleep(0.1)
    assert count_games(server) == 0
    a, _ = await register(open_client, "Alice_A")
    await players(server, (a, "Alice_A"))
    game = await server.games.create_game(g1.player, a.player, TimeControl(600_000, 0), rated=False)
    gid = game.game_id
    await g1.request("move", game_id=gid, move="f2f3", expected_ply=0)
    assert game_status(server, gid) == "active"
    assert (await a.request("history"))["games"] == []             # running games are not listed ...
    assert (await a.request("game_record", game_id=gid))["code"] == P.NOT_FOUND     # ... nor shown
    for who, uci, ply in ((a, "e7e5", 1), (g1, "g2g4", 2), (a, "d8h4", 3)):
        assert (await who.request("move", game_id=gid, move=uci, expected_ply=ply))["type"] == "move_accepted"
    for _ in range(50):                                            # stored by the game-end callback
        if game_status(server, gid) != "active":
            break
        await asyncio.sleep(0.02)
    hist = (await a.request("history"))["games"]
    assert [(h["game_id"], h["opponent"], h["outcome"]) for h in hist] == [(gid, "Guest_Visitor", "win")]
    # Deleting the account removes the game too: it now belongs to nobody.
    assert (await a.request("delete_account", password=PW))["type"] == "account_deleted"
    assert count_games(server) == 0


async def test_a_game_is_recorded_only_once(server):
    rec = {"id": "g1", "white_user_id": None, "black_user_id": None, "white_name": "a", "black_name": "b",
           "rated": False, "initial_ms": 1, "increment_ms": 0, "status": "finished", "result": "1-0",
           "termination": "resignation", "moves": "", "final_fen": "", "pgn": "", "started_at": "x",
           "ended_at": "y"}
    await server.db.save_game(rec)
    await server.db.save_game(rec)
    assert server.db.query_one("SELECT COUNT(*) FROM games")[0] == 1


# --------------------------------------------------------------------------- deletion
async def test_delete_account(open_client, server):
    a, ans = await register(open_client, "Alice_A")
    b, _ = await register(open_client, "Bobby_B")
    await players(server, (a, "Alice_A"), (b, "Bobby_B"))
    gid = await play_short_game(server, a, b)
    await asyncio.sleep(0.1)
    assert (await a.request("delete_account", password="wrong pass"))["code"] == P.FORBIDDEN
    assert (await a.request("delete_account", password=PW))["type"] == "account_deleted"
    again = await (await connected(open_client)).request("login", username="Alice_A", password=PW)
    assert again["code"] == P.FORBIDDEN
    rec = (await b.request("game_record", game_id=gid))["game"]
    assert rec["white"] == "Deleted player"                          # opponent keeps the game
    assert server.db.query_one("SELECT COUNT(*) FROM sessions WHERE user_id = 1")[0] == 0
    # The name can be registered again by someone new.
    await register(open_client, "Alice_A")


# --------------------------------------------------------------------------- storage
def test_migration_3_removes_games_between_guests(tmp_path):
    path = str(tmp_path / "old.db")
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)")
    conn.commit()
    conn.close()
    # Version 2 database with one game between guests and one with an account.
    import beginnerchess_server.persistence as persistence
    files = sorted(MIGRATIONS_DIR.glob("[0-9][0-9][0-9][0-9]_*.sql"))
    conn = sqlite3.connect(path)
    for f in files[:2]:
        for st in _split_sql(f.read_text()):
            conn.execute(st)
        conn.execute("INSERT INTO schema_migrations VALUES (?, 'x')", (int(f.name[:4]),))
    conn.execute("INSERT INTO users(id, username, password_hash, created_at) VALUES (1, 'Alice_A', 'h', 'x')")
    for gid, uid in (("guests", None), ("account", 1)):
        conn.execute("INSERT INTO games(id, white_user_id, black_user_id, white_name, black_name, rated, "
                     "initial_ms, increment_ms, status, moves, started_at) "
                     "VALUES (?, ?, NULL, 'Guest_A', 'Guest_B', 0, 1, 0, 'finished', '', 'x')", (gid, uid))
    conn.commit()
    conn.close()
    db = persistence.Database(path)
    assert db.schema_version() >= 3
    assert [r[0] for r in db.conn.execute("SELECT id FROM games")] == ["account"]
    db.conn.close()


def test_migrations_backup_integrity(tmp_path):
    path = str(tmp_path / "m.db")
    latest = len(list(MIGRATIONS_DIR.glob("[0-9][0-9][0-9][0-9]_*.sql")))
    db = Database(path)
    assert db.schema_version() == latest >= 2
    db.close()
    db = Database(path)                                   # opening again changes nothing
    assert db.schema_version() == latest
    assert db.integrity_check() == "ok"
    db.conn.execute("INSERT INTO users(username, password_hash, created_at) VALUES ('X1y', 'h', 'now')")
    db.backup_to(str(tmp_path / "copy.db"))
    copy = sqlite3.connect(str(tmp_path / "copy.db"))
    assert copy.execute("SELECT username FROM users").fetchone()[0] == "X1y"
    assert copy.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    tables = {r[0] for r in copy.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert {"users", "sessions", "games", "rating_history", "schema_migrations"} <= tables
    fk = copy.execute("PRAGMA foreign_key_list(sessions)").fetchall()
    assert fk and fk[0][2] == "users"
    db.close()


async def test_sql_injection_attempts_are_harmless(open_client, server):
    c = await connected(open_client)
    for name in ["a' OR '1'='1", "x'; DROP TABLE users; --"]:
        r = await c.request("login", username=name, password="whatever1")
        assert r["code"] in (P.FORBIDDEN, P.RATE_LIMITED)
    assert server.db.query_one("SELECT COUNT(*) FROM sqlite_master WHERE name='users'")[0] == 1


def test_upgrade_from_version_1_keeps_data(tmp_path):
    """A database created by the first release is upgraded in place."""
    path = str(tmp_path / "old.db")
    old = sqlite3.connect(path)
    old.execute("CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)")
    for stmt in _split_sql((MIGRATIONS_DIR / "0001_initial.sql").read_text()):
        old.execute(stmt)
    old.execute("INSERT INTO schema_migrations VALUES (1, 'then')")
    old.execute("INSERT INTO users(username, password_hash, created_at, rating) VALUES ('Old_1', 'h', 'then', 1333)")
    old.commit()
    old.close()
    db = Database(path)
    assert db.schema_version() >= 2
    assert db.conn.execute("SELECT username, rating FROM users").fetchone()[:] == ("Old_1", 1333)
    cols = {r[1] for r in db.conn.execute("PRAGMA table_info(games)")}
    assert {"white_key", "white_ms", "seq"} <= cols
    db.close()
