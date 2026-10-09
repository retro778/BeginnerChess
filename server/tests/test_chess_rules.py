"""Chess rules: perft against the standard reference counts, and every special rule."""

from __future__ import annotations

import pytest

from beginnerchess_server.chess_rules import (START_FEN, Board, IllegalPosition, Move, perft,
                                              square)

# Reference positions and counts from the Chess Programming Wiki ("Perft Results").
PERFT = [
    (START_FEN, [20, 400, 8902, 197281]),
    ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039, 97862]),
    ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812, 43238]),
    ("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467]),
    ("r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1", [6, 264, 9467]),
    ("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", [44, 1486, 62379]),
    ("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", [46, 2079, 89890]),
]


@pytest.mark.parametrize("fen, counts", PERFT)
def test_perft(fen, counts):
    board = Board(fen)
    for depth, expected in enumerate(counts, start=1):
        assert perft(board, depth) == expected, f"depth {depth}"
    assert board.fen().split()[:3] == fen.split()[:3]       # make/unmake restored everything


def play(board: Board, *ucis: str) -> None:
    for u in ucis:
        m = Move.from_uci(u)
        assert board.is_legal(m), f"{u} should be legal in {board.fen()}"
        board.push(m)


def test_fen_round_trip():
    for fen, _ in PERFT:
        assert Board(fen).fen() == fen


@pytest.mark.parametrize("fen", [
    "8/8/8/8/8/8/8/8 w - - 0 1",                                # no kings
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1",  # bad side
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBN w KQkq - 0 1",   # short rank
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNRR w KQkq - 0 1",  # long rank
    "4k3/8/8/8/8/8/8/4K2P w - - 0 1",                           # pawn on rank 1
    "4k3/4Q3/8/8/8/8/8/4K3 w - - 0 1",                          # side not to move in check
    "4k3/8/8/8/8/8/8/4K3 w - e3 0 1",                           # impossible ep square
    "4k3/8/8/8/8/8/8/4K3 w - - x 1",                            # bad counter
])
def test_illegal_fens_are_rejected(fen):
    with pytest.raises(IllegalPosition):
        Board(fen)


def test_turn_order_and_basic_legality():
    b = Board()
    assert not b.is_legal(Move.from_uci("e7e5"))                 # black piece, white to move
    assert not b.is_legal(Move.from_uci("e2e5"))                 # pawn cannot jump three
    assert not b.is_legal(Move.from_uci("b1d2"))                 # own piece on d2
    play(b, "e2e4")
    assert b.turn == "b" and not b.is_legal(Move.from_uci("d2d4"))


def test_castling_rules():
    b = Board("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    assert b.is_legal(Move.from_uci("e1g1")) and b.is_legal(Move.from_uci("e1c1"))
    play(b, "e1g1")
    assert b.squares[square("f1")] == "R" and b.squares[square("g1")] == "K"
    assert b.castling == "kq"
    # Not through or out of check, not into check.
    assert not Board("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1").is_legal(Move.from_uci("e1e3"))
    through = Board("4k3/8/8/8/8/8/5r2/R3K2R w KQ - 0 1")       # rook on f2 attacks f1
    assert not through.is_legal(Move.from_uci("e1g1")) and through.is_legal(Move.from_uci("e1c1"))
    in_check = Board("4k3/8/8/8/8/8/4r3/R3K2R w KQ - 0 1")
    assert not in_check.is_legal(Move.from_uci("e1g1")) and not in_check.is_legal(Move.from_uci("e1c1"))
    b1_attacked = Board("4k3/8/8/8/8/8/1r6/R3K2R w KQ - 0 1")    # b1 attacked: queen side still allowed
    assert b1_attacked.is_legal(Move.from_uci("e1c1"))
    # Rights are lost when the rook moves or is captured.
    b = Board("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    play(b, "a1a8")
    assert b.castling == "Kk"


def test_en_passant():
    b = Board()
    play(b, "e2e4", "a7a6", "e4e5", "d7d5")
    assert b.fen().split()[3] == "d6"
    play(b, "e5d6")
    assert b.squares[square("d5")] is None and b.squares[square("d6")] == "P"
    # Only right after the double step.
    b = Board()
    play(b, "e2e4", "a7a6", "e4e5", "d7d5", "a2a3", "a6a5")
    assert not b.is_legal(Move.from_uci("e5d6"))
    # Not if it exposes the king (horizontal pin).
    pinned = Board("8/8/8/KPp4r/8/8/8/7k w - c6 0 1")
    assert not pinned.is_legal(Move.from_uci("b5c6"))
    assert pinned.fen().split()[3] == "-"                       # not capturable -> not in FEN


def test_promotion():
    b = Board("8/P6k/8/8/8/8/8/K7 w - - 0 1")
    assert not b.is_legal(Move(square("a7"), square("a8")))     # must name the piece
    for p in "qrbn":
        assert b.is_legal(Move(square("a7"), square("a8"), p))
    play(b, "a7a8n")
    assert b.squares[square("a8")] == "N"
    with pytest.raises(ValueError):
        Move.from_uci("a7a8k")


def test_checkmate_and_stalemate():
    b = Board()
    play(b, "f2f3", "e7e5", "g2g4", "d8h4")
    assert b.is_checkmate() and b.automatic_end() == ("0-1", "checkmate")
    s = Board("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
    assert s.is_stalemate() and s.automatic_end() == ("1/2-1/2", "stalemate")


def test_threefold_and_fivefold_repetition():
    b = Board()
    shuffle = ["g1f3", "g8f6", "f3g1", "f6g8"]
    play(b, *shuffle)
    assert b.repetitions() == 2 and not b.can_claim_threefold()
    play(b, *shuffle)
    assert b.can_claim_threefold() and b.automatic_end() is None
    play(b, *shuffle, *shuffle)
    assert b.repetitions() == 5 and b.automatic_end() == ("1/2-1/2", "fivefold_repetition")


def test_en_passant_right_changes_the_position_for_repetitions():
    # After 1.e4 the e3 square is not capturable: same position as without it.
    a = Board("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1")
    play(a, "e2e4")
    assert a.position_key() == Board("4k3/8/8/8/4P3/8/8/4K3 b - - 0 1").position_key()
    # With a black pawn on d4 the capture is possible: a different position.
    b = Board("4k3/8/8/8/3p4/8/4P3/4K3 w - - 0 1")
    play(b, "e2e4")
    assert b.position_key() != Board("4k3/8/8/8/3pP3/8/8/4K3 b - - 0 1").position_key()


def test_fifty_and_seventyfive_move_rules():
    b = Board("4k3/8/8/8/8/8/8/R3K3 w - - 99 80")
    assert not b.can_claim_fifty_moves()
    play(b, "a1a2")
    assert b.can_claim_fifty_moves() and b.automatic_end() is None
    c = Board("4k3/8/8/8/8/8/8/R3K3 w - - 149 80")
    play(c, "a1a2")
    assert c.automatic_end() == ("1/2-1/2", "seventyfive_moves")
    # Checkmate on the 75th move counts as checkmate.
    m = Board("6k1/5ppp/8/8/8/8/8/R5K1 w - - 149 80")
    play(m, "a1a8")
    assert m.automatic_end() == ("1-0", "checkmate")
    # A pawn move resets the counter.
    r = Board("4k3/8/8/8/8/8/4P3/4K3 w - - 98 80")
    play(r, "e2e4")
    assert r.halfmove == 0


@pytest.mark.parametrize("fen, white_insufficient, black_insufficient, dead", [
    ("4k3/8/8/8/8/8/8/4K3 w - - 0 1", True, True, True),                 # K v K
    ("4k3/8/8/8/8/8/8/2B1K3 w - - 0 1", True, True, True),               # K+B v K
    ("4k3/8/8/8/8/8/8/1N2K3 w - - 0 1", True, True, True),               # K+N v K
    ("4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1", True, True, True),              # bishops on same colour
    ("4k1b1/8/8/8/8/8/8/2B1K3 w - - 0 1", False, False, False),          # opposite colours
    ("4k3/8/8/8/8/8/8/NN2K3 w - - 0 1", False, True, False),             # two knights can (help)mate
    ("4k3/4p3/8/8/8/8/8/1N2K3 w - - 0 1", False, False, False),          # knight + enemy pawn
    ("4k3/8/8/8/8/8/8/3QK3 w - - 0 1", False, True, False),
    ("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", False, True, False),
])
def test_insufficient_material(fen, white_insufficient, black_insufficient, dead):
    b = Board(fen)
    assert b.has_insufficient_material("w") == white_insufficient
    assert b.has_insufficient_material("b") == black_insufficient
    assert b.is_insufficient_material() == dead


@pytest.mark.parametrize("fen, uci, san", [
    (START_FEN, "g1f3", "Nf3"),
    (START_FEN, "e2e4", "e4"),
    ("4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1", "e1g1", "O-O"),
    ("4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1", "e1c1", "O-O-O"),
    ("4k3/8/8/8/8/8/4K3/R6R w - - 0 1", "a1d1", "Rad1"),          # file disambiguation
    ("4k3/8/8/R7/8/8/8/R3K3 w - - 0 1", "a1a3", "R1a3"),           # rank disambiguation
    ("k7/8/8/8/8/2Q1Q3/8/2Q1K3 w - - 0 1", "c3d2", "Qc3d2"),       # both needed
    ("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1", "e4d5", "exd5"),
    ("8/P6k/8/8/8/8/8/K7 w - - 0 1", "a7a8q", "a8=Q"),
    ("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", "a1a8", "Ra8#"),
    ("4k3/8/8/8/8/8/8/R3K3 w - - 0 1", "a1a8", "Ra8+"),
])
def test_san(fen, uci, san):
    b = Board(fen)
    assert b.san(Move.from_uci(uci)) == san
    assert b.fen() == Board(fen).fen()                          # san() changes nothing


def test_bad_uci():
    for text in ["", "e2", "e2e9", "z2e4", "e2e4qq", "e7e8k", 42]:
        with pytest.raises(ValueError):
            Move.from_uci(text)  # type: ignore[arg-type]


def test_same_moves_as_the_client():
    """The server and the BeginnerChess client must agree on every legal move:
    random positions are counted with both move generators (perft 2)."""
    import random
    import re
    import subprocess
    from pathlib import Path
    client = Path(__file__).resolve().parents[2] / "tests" / "test_core"
    if not client.exists():
        pytest.skip("client test program not built (./build.sh)")
    rng = random.Random(7)
    checked = 0
    for _ in range(60):
        b = Board()
        for _ in range(rng.randint(10, 90)):
            moves = b.legal_moves()
            if not moves or b.automatic_end():
                break
            b.push(rng.choice(moves))
        fen = b.fen()
        out = subprocess.run([str(client), "--perft", fen, "2"], capture_output=True, text=True,
                             timeout=30).stdout
        assert int(re.search(r"perft\(2\) = (\d+)", out).group(1)) == perft(Board(fen), 2), fen
        checked += 1
    assert checked == 60
