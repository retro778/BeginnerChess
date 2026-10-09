"""Phase 3: authoritative games over real WebSocket connections."""

from __future__ import annotations

import asyncio

import pytest

from beginnerchess_server import protocol as P
from beginnerchess_server.chess_rules import Board
from beginnerchess_server.config import Config
from beginnerchess_server.games import TimeControl
from beginnerchess_server.players import Player, new_guest_id

TEN_MIN = TimeControl(600_000, 0)


async def logged_in(open_client, server, name: str):
    """A greeted client with a player identity (login itself arrives in phase 5)."""
    c = await open_client()
    await c.hello()
    player = Player(new_guest_id(), name, "guest")
    # Find the server-side connection of this client and attach the identity.
    for _ in range(100):
        clients = [x for x in server.registry.clients.values()
                   if x.greeted and x.identity is None]
        if clients:
            break
        await asyncio.sleep(0.01)
    server.presence.attach(player, clients[-1])
    c.player = player
    return c


async def wait_for(c, mtype: str, timeout: float = 5.0) -> dict:
    """Next message of the given type (other messages are kept in c.events)."""
    for i, ev in enumerate(c.events):
        if ev["type"] == mtype:
            return c.events.pop(i)
    loop = asyncio.get_running_loop()
    end = loop.time() + timeout
    while True:
        msg = await c.recv(timeout=max(0.01, end - loop.time()))
        if msg["type"] == mtype:
            return msg
        c.events.append(msg)


@pytest.fixture
async def pair(open_client, server):
    """White and black, both logged in, with a started 10-minute game."""
    white = await logged_in(open_client, server, "Guest_White")
    black = await logged_in(open_client, server, "Guest_Black")
    game = await server.games.create_game(white.player, black.player, TEN_MIN, rated=False)
    w0 = await wait_for(white, "game_started")
    b0 = await wait_for(black, "game_started")
    return white, black, game, w0, b0


async def move(c, game_id: str, uci: str, ply: int, **extra) -> dict:
    return await c.request("move", game_id=game_id, move=uci, expected_ply=ply, **extra)


# --------------------------------------------------------------------------- start
async def test_game_started_snapshot(pair):
    white, black, game, w0, b0 = pair
    assert w0["game"]["your_color"] == "w" and b0["game"]["your_color"] == "b"
    g = w0["game"]
    assert g["ply"] == 0 and g["turn"] == "w" and g["status"] == "active"
    assert g["white"] == {"name": "Guest_White", "kind": "guest"}
    assert g["clock"]["white_ms"] == 600_000 and g["clock"]["running"] is None
    assert 0 < g["clock"]["first_move_ms"] <= 30_000
    assert g["fen"].startswith("rnbqkbnr/pppppppp")


async def test_a_complete_game_with_checkmate(pair):
    white, black, game, *_ = pair
    gid = game.game_id
    script = [(white, "f2f3"), (black, "e7e5"), (white, "g2g4"), (black, "d8h4")]
    for ply, (who, uci) in enumerate(script):
        answer = await move(who, gid, uci, ply)
        assert answer["type"] == "move_accepted" and answer["ply"] == ply + 1
        opponent = black if who is white else white
        seen = await wait_for(opponent, "move_accepted")
        assert seen["move"] == uci and "request_id" not in seen      # event for the opponent
        assert seen["fen"] == answer["fen"]                           # both boards agree
    assert answer["san"] == "Qh4#"
    for c in (white, black):
        over = await wait_for(c, "game_over")
        assert over["result"] == "0-1" and over["termination"] == "checkmate"
        assert "1. f3 e5 2. g4 Qh4# 0-1" in over["pgn"]
    assert not server_games_active(game)


def server_games_active(game) -> bool:
    return game.status == "active"


async def test_illegal_wrong_turn_stale_and_bad_moves(pair):
    white, black, game, *_ = pair
    gid = game.game_id
    assert (await move(white, gid, "e2e5", 0))["code"] == P.ILLEGAL_MOVE
    assert (await move(black, gid, "e7e5", 0))["code"] == P.NOT_YOUR_TURN
    assert (await move(white, gid, "e2e4", 3))["code"] == P.CONFLICT
    bad = await move(white, gid, "e2x4", 0)
    assert bad["code"] == P.BAD_MESSAGE
    assert (await move(white, gid, "e2e4", 0))["type"] == "move_accepted"
    stale = await move(black, gid, "e7e5", 0)
    assert stale["code"] == P.CONFLICT and stale["current_ply"] == 1
    assert game.ply == 1                                          # nothing else was played


async def test_retry_of_an_accepted_move_is_not_played_twice(pair):
    white, black, game, *_ = pair
    first = await move(white, game.game_id, "e2e4", 0)
    again = await move(white, game.game_id, "e2e4", 0)              # e.g. resent after a timeout
    assert first["type"] == again["type"] == "move_accepted"
    assert again["duplicate"] is True and again["ply"] == 1 and game.ply == 1


async def test_simultaneous_requests(pair):
    white, black, game, *_ = pair
    gid = game.game_id
    await white.send({"type": "move", "request_id": "a", "game_id": gid, "move": "e2e4", "expected_ply": 0})
    await white.send({"type": "move", "request_id": "b", "game_id": gid, "move": "d2d4", "expected_ply": 0})
    answers = {}
    while len(answers) < 2:
        msg = await white.recv()
        if msg.get("request_id") in ("a", "b"):
            answers[msg["request_id"]] = msg
    assert answers["a"]["type"] == "move_accepted"
    assert answers["b"]["code"] == P.NOT_YOUR_TURN
    assert game.ucis == ["e2e4"]


async def test_strangers_and_anonymous_clients_cannot_touch_a_game(pair, open_client, server):
    white, black, game, *_ = pair
    stranger = await logged_in(open_client, server, "Guest_Eve")
    assert (await move(stranger, game.game_id, "e2e4", 0))["code"] == P.NOT_FOUND
    assert (await stranger.request("game_state", game_id=game.game_id))["code"] == P.NOT_FOUND
    assert (await stranger.request("resign", game_id=game.game_id))["code"] == P.NOT_FOUND
    anonymous = await open_client()
    await anonymous.hello()
    assert (await move(anonymous, game.game_id, "e2e4", 0))["code"] == P.NOT_AUTHENTICATED
    assert game.ply == 0 and game.status == "active"


async def test_game_state_snapshot(pair):
    white, black, game, *_ = pair
    await move(white, game.game_id, "e2e4", 0)
    await move(black, game.game_id, "c7c5", 1)
    snap = (await black.request("game_state", game_id=game.game_id))["game"]
    assert snap["moves"] == ["e2e4", "c7c5"] and snap["san"] == ["e4", "c5"]
    assert snap["ply"] == 2 and snap["your_color"] == "b"
    assert snap["clock"]["running"] == "w"
    assert snap["fen"] == Board(snap["fen"]).fen()


# --------------------------------------------------------------------------- endings
async def test_resignation(pair):
    white, black, game, *_ = pair
    await move(white, game.game_id, "e2e4", 0)
    await move(black, game.game_id, "e7e5", 1)
    answer = await black.request("resign", game_id=game.game_id)       # not black's turn: allowed
    assert answer["type"] == "game_over" and answer["result"] == "1-0"
    assert (await wait_for(white, "game_over"))["termination"] == "resignation"
    assert (await move(white, game.game_id, "g1f3", 2))["code"] == P.GAME_OVER


async def test_resign_or_abort_before_the_first_moves_aborts(pair, open_client, server):
    white, black, game, *_ = pair
    answer = await white.request("resign", game_id=game.game_id)
    assert answer["status"] == "aborted" and answer["result"] is None
    # After both sides have moved, aborting is no longer possible.
    g2 = await server.games.create_game(white.player, black.player, TEN_MIN, rated=False)
    await move(white, g2.game_id, "e2e4", 0)
    await move(black, g2.game_id, "e7e5", 1)
    assert (await white.request("abort", game_id=g2.game_id))["code"] == P.CONFLICT


async def test_draw_offer_decline_accept(pair):
    white, black, game, *_ = pair
    gid = game.game_id
    await move(white, gid, "e2e4", 0)
    await move(black, gid, "e7e5", 1)
    assert (await white.request("offer_draw", game_id=gid))["type"] == "ok"
    assert (await wait_for(black, "draw_offered"))["by"] == "white"
    assert (await white.request("offer_draw", game_id=gid))["code"] == P.CONFLICT     # already offered
    assert (await black.request("decline_draw", game_id=gid))["type"] == "ok"
    await wait_for(white, "draw_declined")
    assert (await white.request("offer_draw", game_id=gid))["code"] == P.CONFLICT     # not again this move
    assert (await white.request("accept_draw", game_id=gid))["code"] == P.CONFLICT    # nothing to accept
    await move(white, gid, "g1f3", 2)
    await black.request("offer_draw", game_id=gid)
    await wait_for(white, "draw_offered")
    over = await white.request("accept_draw", game_id=gid)
    assert over["result"] == "1/2-1/2" and over["termination"] == "agreement"


async def test_moving_declines_a_draw_offer(pair):
    white, black, game, *_ = pair
    gid = game.game_id
    await move(white, gid, "e2e4", 0)
    await white.request("offer_draw", game_id=gid)
    answer = await move(black, gid, "e7e5", 1)
    assert answer["draw_offer"] is None
    assert (await black.request("accept_draw", game_id=gid))["code"] == P.CONFLICT


async def test_both_offering_is_an_agreement(pair):
    white, black, game, *_ = pair
    gid = game.game_id
    await move(white, gid, "e2e4", 0)
    await white.request("offer_draw", game_id=gid)
    over = await black.request("offer_draw", game_id=gid)
    assert over["type"] == "game_over" and over["termination"] == "agreement"


async def test_threefold_repetition_claim(pair):
    white, black, game, *_ = pair
    gid = game.game_id
    shuffle = [(white, "g1f3"), (black, "g8f6"), (white, "f3g1"), (black, "f6g8")]
    ply = 0
    for who, uci in shuffle * 2:
        answer = await move(who, gid, uci, ply)
        ply += 1
    assert answer["can_claim_draw"] is True                           # third occurrence
    assert (await black.request("claim_draw", game_id=gid))["code"] == P.NOT_YOUR_TURN
    over = await white.request("claim_draw", game_id=gid)
    assert over["result"] == "1/2-1/2" and over["termination"] == "threefold_repetition"


async def test_claim_with_the_move_that_repeats(pair):
    white, black, game, *_ = pair
    gid = game.game_id
    shuffle = [(white, "g1f3"), (black, "g8f6"), (white, "f3g1"), (black, "f6g8")]
    ply = 0
    for who, uci in (shuffle * 2)[:-1]:
        await move(who, gid, uci, ply)
        ply += 1
    await move(black, gid, "f6g8", ply, claim_draw=True)               # creates the 3rd repetition
    over = await wait_for(white, "game_over")
    assert over["termination"] == "threefold_repetition"


async def test_invalid_claim_is_refused(pair):
    white, black, game, *_ = pair
    assert (await white.request("claim_draw", game_id=game.game_id))["code"] == P.CONFLICT
    answer = await move(white, game.game_id, "e2e4", 0, claim_draw=True)
    assert answer["type"] == "move_accepted" and game.status == "active"


# --------------------------------------------------------------------------- clocks
async def test_first_move_timeout_aborts(open_client, server):
    white = await logged_in(open_client, server, "Guest_A")
    black = await logged_in(open_client, server, "Guest_B")
    server.games.first_move_ms = 300
    game = await server.games.create_game(white.player, black.player, TEN_MIN, rated=False)
    over = await wait_for(white, "game_over", timeout=3)
    assert over["status"] == "aborted" and over["termination"] == "first_move_timeout"
    assert not server.games.is_playing(white.player)


async def test_clock_runs_out(open_client, server):
    white = await logged_in(open_client, server, "Guest_A")
    black = await logged_in(open_client, server, "Guest_B")
    game = await server.games.create_game(white.player, black.player, TimeControl(400, 0), rated=False)
    await move(white, game.game_id, "e2e4", 0)
    await move(black, game.game_id, "e7e5", 1)          # now white's clock runs (0.4 s)
    over = await wait_for(black, "game_over", timeout=3)
    assert over["result"] == "0-1" and over["termination"] == "timeout"
    assert over["clock"]["white_ms"] == 0


async def test_timeout_against_lone_king_is_a_draw(open_client, server):
    white = await logged_in(open_client, server, "Guest_A")
    black = await logged_in(open_client, server, "Guest_B")
    game = await server.games.create_game(white.player, black.player, TimeControl(400, 0), rated=False)
    await move(white, game.game_id, "e2e4", 0)
    await move(black, game.game_id, "e7e5", 1)
    game.board = Board("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1")    # black has only the king left
    over = await wait_for(black, "game_over", timeout=3)
    assert over["result"] == "1/2-1/2" and over["termination"] == "timeout_vs_insufficient_material"


async def test_late_move_after_time_is_up_is_refused(open_client, server):
    white = await logged_in(open_client, server, "Guest_A")
    black = await logged_in(open_client, server, "Guest_B")
    game = await server.games.create_game(white.player, black.player, TimeControl(200, 0), rated=False)
    await move(white, game.game_id, "e2e4", 0)
    await move(black, game.game_id, "e7e5", 1)
    if game.timer:
        game.timer.cancel()                      # simulate the timer not having fired yet
    await asyncio.sleep(0.3)
    answer = await move(white, game.game_id, "g1f3", 2)
    assert answer["code"] == P.GAME_OVER and game.termination == "timeout"


async def test_increment_and_clock_accounting(open_client, server):
    white = await logged_in(open_client, server, "Guest_A")
    black = await logged_in(open_client, server, "Guest_B")
    game = await server.games.create_game(white.player, black.player, TimeControl(60_000, 2_000), rated=False)
    await move(white, game.game_id, "e2e4", 0)
    await move(black, game.game_id, "e7e5", 1)
    await asyncio.sleep(0.3)
    answer = await move(white, game.game_id, "g1f3", 2)
    white_ms = answer["clock"]["white_ms"]
    assert 61_500 <= white_ms <= 61_750           # 60 s - ~0.3 s thinking + 2 s increment
    assert answer["clock"]["black_ms"] == 60_000  # black's first move was before the clocks started
    assert answer["clock"]["running"] == "b"


def test_time_control_validation():
    assert TimeControl.from_request({"initial_seconds": 600, "increment_seconds": 5}) == TimeControl(600_000, 5_000)
    for bad in [{"initial_seconds": 601, "increment_seconds": 0},
                {"initial_seconds": 600, "increment_seconds": 3},
                {"initial_seconds": "600", "increment_seconds": 0},
                {"initial_seconds": 600}, None]:
        with pytest.raises(P.ProtocolError):
            TimeControl.from_request(bad)


async def test_one_game_at_a_time(pair, server):
    white, black, game, *_ = pair
    with pytest.raises(P.ProtocolError):
        await server.games.create_game(white.player, black.player, TEN_MIN, rated=False)


@pytest.mark.parametrize("config", [Config(listen_port=0, rate_limit_burst=1000, rate_limit_per_second=1000,
                                           max_connections_per_ip=50, database_path=":memory:")])
async def test_random_games_stay_synchronised(open_client, server):
    """Complete random games: both clients replay the accepted moves on their own
    boards and must always agree with the server (FEN after every move)."""
    import random
    from beginnerchess_server.chess_rules import Move
    rng = random.Random(11)
    white = await logged_in(open_client, server, "Guest_A")
    black = await logged_in(open_client, server, "Guest_B")
    endings = set()
    for _ in range(6):
        game = await server.games.create_game(white.player, black.player, TEN_MIN, rated=False)
        await wait_for(white, "game_started")
        await wait_for(black, "game_started")
        boards = {white: Board(), black: Board()}
        while game.status == "active":
            mover = white if boards[white].turn == "w" else black
            other_c = black if mover is white else white
            legal = boards[mover].legal_moves()
            uci = rng.choice(legal).uci()
            answer = await move(mover, game.game_id, uci, len(boards[mover].move_stack))
            assert answer["type"] == "move_accepted", answer
            event = await wait_for(other_c, "move_accepted")
            for c, msg in ((mover, answer), (other_c, event)):
                boards[c].push(Move.from_uci(msg["move"]))
                assert boards[c].fen() == msg["fen"] == game.board.fen()
            if game.ply > 300:                       # keep the test short
                over = await white.request("resign", game_id=game.game_id)
                assert over["type"] == "game_over"
                white.events.append(over)            # the resigner's answer is its game_over
        for c in (white, black):
            over = await wait_for(c, "game_over")
        endings.add(over["termination"])
    assert endings                                      # every game ended properly
