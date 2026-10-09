"""Complete chess rules for the server (BeginnerChess's own implementation, MIT).

Squares are 0..63 with a1 = 0, b1 = 1, ..., h8 = 63. Pieces are the FEN
letters (``PNBRQK`` white, ``pnbrqk`` black); empty squares are ``None``.

Verified with perft against the standard reference positions (tests) and
against the BeginnerChess client's move generator.
"""

from __future__ import annotations

from dataclasses import dataclass

START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

WHITE, BLACK = "w", "b"
FILES = "abcdefgh"

KNIGHT_STEPS = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
KING_STEPS = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
BISHOP_DIRS = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
ROOK_DIRS = [(1, 0), (-1, 0), (0, 1), (0, -1)]
QUEEN_DIRS = BISHOP_DIRS + ROOK_DIRS


def square(name: str) -> int:
    """'e4' -> 28. Raises ValueError for anything else."""
    if len(name) != 2 or name[0] not in FILES or name[1] not in "12345678":
        raise ValueError(f"not a square: {name!r}")
    return FILES.index(name[0]) + 8 * (int(name[1]) - 1)


def square_name(sq: int) -> str:
    return FILES[sq & 7] + str((sq >> 3) + 1)


def _off(sq: int, df: int, dr: int) -> int | None:
    f, r = (sq & 7) + df, (sq >> 3) + dr
    if 0 <= f < 8 and 0 <= r < 8:
        return f + 8 * r
    return None


# Precomputed neighbour tables (much faster than recomputing every time).
KNIGHT_TARGETS = [[t for t in (_off(s, df, dr) for df, dr in KNIGHT_STEPS) if t is not None] for s in range(64)]
KING_TARGETS = [[t for t in (_off(s, df, dr) for df, dr in KING_STEPS) if t is not None] for s in range(64)]
RAYS: dict[tuple[int, int], list[list[int]]] = {}
for _d in QUEEN_DIRS:
    RAYS[_d] = []
    for _s in range(64):
        ray, t = [], _off(_s, *_d)
        while t is not None:
            ray.append(t)
            t = _off(t, *_d)
        RAYS[_d].append(ray)


def colour_of(piece: str) -> str:
    return WHITE if piece.isupper() else BLACK


@dataclass(frozen=True)
class Move:
    frm: int
    to: int
    promotion: str | None = None      # 'q', 'r', 'b', 'n'

    def uci(self) -> str:
        return square_name(self.frm) + square_name(self.to) + (self.promotion or "")

    @staticmethod
    def from_uci(text: str) -> "Move":
        """Parses 'e2e4' or 'e7e8q'. Raises ValueError."""
        if not isinstance(text, str) or len(text) not in (4, 5):
            raise ValueError("a move is written like e2e4 or e7e8q")
        promo = text[4] if len(text) == 5 else None
        if promo is not None and promo not in "qrbn":
            raise ValueError("promotion must be q, r, b or n")
        return Move(square(text[:2]), square(text[2:4]), promo)


class IllegalPosition(ValueError):
    pass


@dataclass
class _Undo:
    move: Move
    captured: str | None
    captured_sq: int
    castling: str
    ep: int | None
    halfmove: int
    fullmove: int
    moved: str


class Board:
    """A chess position with move history (for repetitions and undo)."""

    def __init__(self, fen: str = START_FEN):
        self.squares: list[str | None] = [None] * 64
        self.turn = WHITE
        self.castling = ""
        self.ep: int | None = None          # en passant target square (as in FEN)
        self.halfmove = 0
        self.fullmove = 1
        self._undo: list[_Undo] = []
        self._keys: list[tuple] = []        # position keys, oldest first
        self.set_fen(fen)

    # ------------------------------------------------------------------ FEN
    def set_fen(self, fen: str) -> None:
        parts = fen.split()
        if len(parts) != 6:
            raise IllegalPosition("FEN needs 6 fields")
        placement, turn, castling, ep, half, full = parts
        rows = placement.split("/")
        if len(rows) != 8:
            raise IllegalPosition("FEN needs 8 ranks")
        squares: list[str | None] = [None] * 64
        for i, row in enumerate(rows):
            rank, f = 7 - i, 0
            for ch in row:
                if ch.isdigit() and ch != "0":
                    f += int(ch)
                elif ch in "PNBRQKpnbrqk":
                    if f > 7:
                        raise IllegalPosition("rank too long")
                    squares[f + 8 * rank] = ch
                    f += 1
                else:
                    raise IllegalPosition(f"bad character {ch!r}")
            if f != 8:
                raise IllegalPosition("every rank needs 8 squares")
        if turn not in (WHITE, BLACK):
            raise IllegalPosition("side to move must be w or b")
        if castling != "-" and (any(c not in "KQkq" for c in castling) or len(set(castling)) != len(castling)):
            raise IllegalPosition("bad castling field")
        if squares.count("K") != 1 or squares.count("k") != 1:
            raise IllegalPosition("each side needs exactly one king")
        if any(squares[s] in ("P", "p") for s in list(range(8)) + list(range(56, 64))):
            raise IllegalPosition("pawns cannot stand on the first or last rank")
        try:
            halfmove, fullmove = int(half), int(full)
        except ValueError:
            raise IllegalPosition("move counters must be numbers") from None
        if halfmove < 0 or fullmove < 1:
            raise IllegalPosition("bad move counters")
        self.squares, self.turn = squares, turn
        # Keep only castling rights that are possible (king and rook at home).
        rights = ""
        for c, k_sq, r_sq, k, r in (("K", 4, 7, "K", "R"), ("Q", 4, 0, "K", "R"),
                                    ("k", 60, 63, "k", "r"), ("q", 60, 56, "k", "r")):
            if c in castling and squares[k_sq] == k and squares[r_sq] == r:
                rights += c
        self.castling = rights
        self.ep = None
        if ep != "-":
            try:
                ep_sq = square(ep)
            except ValueError:
                raise IllegalPosition("bad en passant square") from None
            if (ep_sq >> 3) != (5 if turn == WHITE else 2):
                raise IllegalPosition("bad en passant square")
            self.ep = ep_sq
        self.halfmove, self.fullmove = halfmove, fullmove
        if self.is_attacked(self.king_square(self._other(turn)), turn):
            raise IllegalPosition("the side not to move is in check")
        self._undo = []
        self._keys = [self.position_key()]

    def fen(self) -> str:
        rows = []
        for rank in range(7, -1, -1):
            row, empty = "", 0
            for f in range(8):
                p = self.squares[f + 8 * rank]
                if p is None:
                    empty += 1
                else:
                    row += (str(empty) if empty else "") + p
                    empty = 0
            rows.append(row + (str(empty) if empty else ""))
        ep = square_name(self.ep) if self.ep is not None and self._ep_capturable() else "-"
        return f"{'/'.join(rows)} {self.turn} {self.castling or '-'} {ep} {self.halfmove} {self.fullmove}"

    # ------------------------------------------------------------------ helpers
    @staticmethod
    def _other(side: str) -> str:
        return BLACK if side == WHITE else WHITE

    def king_square(self, side: str) -> int:
        return self.squares.index("K" if side == WHITE else "k")

    def is_attacked(self, sq: int, by: str) -> bool:
        """Is square ``sq`` attacked by side ``by``?"""
        s = self.squares
        white = by == WHITE
        # Pawns: a white pawn attacks diagonally upwards, so look one rank down.
        pawn = "P" if white else "p"
        dr = -1 if white else 1
        for df in (-1, 1):
            t = _off(sq, df, dr)
            if t is not None and s[t] == pawn:
                return True
        knight, king = ("N", "K") if white else ("n", "k")
        if any(s[t] == knight for t in KNIGHT_TARGETS[sq]):
            return True
        if any(s[t] == king for t in KING_TARGETS[sq]):
            return True
        rook_like = ("R", "Q") if white else ("r", "q")
        bishop_like = ("B", "Q") if white else ("b", "q")
        for d in ROOK_DIRS:
            for t in RAYS[d][sq]:
                p = s[t]
                if p is not None:
                    if p in rook_like:
                        return True
                    break
        for d in BISHOP_DIRS:
            for t in RAYS[d][sq]:
                p = s[t]
                if p is not None:
                    if p in bishop_like:
                        return True
                    break
        return False

    def in_check(self, side: str | None = None) -> bool:
        side = side or self.turn
        return self.is_attacked(self.king_square(side), self._other(side))

    # ------------------------------------------------------------------ move generation
    def pseudo_moves(self) -> list[Move]:
        moves: list[Move] = []
        s, side = self.squares, self.turn
        white = side == WHITE
        for frm, p in enumerate(s):
            if p is None or (p.isupper() != white):
                continue
            kind = p.upper()
            if kind == "P":
                self._pawn_moves(frm, white, moves)
            elif kind == "N":
                for t in KNIGHT_TARGETS[frm]:
                    q = s[t]
                    if q is None or q.isupper() != white:
                        moves.append(Move(frm, t))
            elif kind == "K":
                for t in KING_TARGETS[frm]:
                    q = s[t]
                    if q is None or q.isupper() != white:
                        moves.append(Move(frm, t))
                self._castling_moves(frm, white, moves)
            else:
                dirs = BISHOP_DIRS if kind == "B" else ROOK_DIRS if kind == "R" else QUEEN_DIRS
                for d in dirs:
                    for t in RAYS[d][frm]:
                        q = s[t]
                        if q is None:
                            moves.append(Move(frm, t))
                        else:
                            if q.isupper() != white:
                                moves.append(Move(frm, t))
                            break
        return moves

    def _pawn_moves(self, frm: int, white: bool, moves: list[Move]) -> None:
        s = self.squares
        step = 8 if white else -8
        start_rank, last_rank = (1, 7) if white else (6, 0)
        rank = frm >> 3

        def add(to: int) -> None:
            if (to >> 3) == last_rank:
                for promo in "qrbn":
                    moves.append(Move(frm, to, promo))
            else:
                moves.append(Move(frm, to))

        one = frm + step
        if 0 <= one < 64 and s[one] is None:
            add(one)
            two = one + step
            if rank == start_rank and s[two] is None:
                moves.append(Move(frm, two))
        for df in (-1, 1):
            t = _off(frm, df, 1 if white else -1)
            if t is None:
                continue
            q = s[t]
            if q is not None and q.isupper() != white:
                add(t)
            elif t == self.ep and q is None:
                moves.append(Move(frm, t))

    def _castling_moves(self, frm: int, white: bool, moves: list[Move]) -> None:
        home = 4 if white else 60
        if frm != home or not self.castling:
            return
        enemy = BLACK if white else WHITE
        rook = "R" if white else "r"
        s = self.squares
        king_side, queen_side = ("K", "Q") if white else ("k", "q")
        if king_side in self.castling and s[home + 3] == rook and s[home + 1] is None and s[home + 2] is None:
            if not any(self.is_attacked(x, enemy) for x in (home, home + 1, home + 2)):
                moves.append(Move(home, home + 2))
        if queen_side in self.castling and s[home - 4] == rook and s[home - 1] is None \
                and s[home - 2] is None and s[home - 3] is None:
            if not any(self.is_attacked(x, enemy) for x in (home, home - 1, home - 2)):
                moves.append(Move(home, home - 2))

    def legal_moves(self) -> list[Move]:
        side = self.turn
        legal = []
        for m in self.pseudo_moves():
            self._make(m)
            if not self.is_attacked(self.king_square(side), self.turn):
                legal.append(m)
            self._unmake()
        return legal

    def is_legal(self, move: Move) -> bool:
        return move in self.legal_moves()

    # ------------------------------------------------------------------ making moves
    def _make(self, m: Move) -> None:
        s = self.squares
        piece = s[m.frm]
        assert piece is not None
        white = piece.isupper()
        captured_sq = m.to
        captured = s[m.to]
        if piece in ("P", "p") and m.to == self.ep and captured is None:
            captured_sq = m.to - 8 if white else m.to + 8      # en passant
            captured = s[captured_sq]
        self._undo.append(_Undo(m, captured, captured_sq, self.castling, self.ep,
                                self.halfmove, self.fullmove, piece))
        s[captured_sq] = None
        s[m.frm] = None
        s[m.to] = (m.promotion.upper() if white else m.promotion) if m.promotion else piece
        if piece in ("K", "k") and abs(m.to - m.frm) == 2:              # castling: move the rook
            if m.to > m.frm:
                s[m.frm + 1], s[m.frm + 3] = s[m.frm + 3], None
            else:
                s[m.frm - 1], s[m.frm - 4] = s[m.frm - 4], None
        # Castling rights disappear when the king or a rook moves or a rook is captured.
        for sq, right in ((4, "KQ"), (60, "kq"), (0, "Q"), (7, "K"), (56, "q"), (63, "k")):
            if m.frm == sq or m.to == sq:
                self.castling = "".join(c for c in self.castling if c not in right)
        self.ep = None
        if piece in ("P", "p") and abs(m.to - m.frm) == 16:
            self.ep = (m.frm + m.to) // 2
        self.halfmove = 0 if (piece in ("P", "p") or captured is not None) else self.halfmove + 1
        if not white:
            self.fullmove += 1
        self.turn = self._other(self.turn)

    def _unmake(self) -> None:
        u = self._undo.pop()
        m, s = u.move, self.squares
        s[m.frm] = u.moved
        s[m.to] = None
        if u.captured is not None:
            s[u.captured_sq] = u.captured
        if u.moved in ("K", "k") and abs(m.to - m.frm) == 2:
            if m.to > m.frm:
                s[m.frm + 3], s[m.frm + 1] = s[m.frm + 1], None
            else:
                s[m.frm - 4], s[m.frm - 1] = s[m.frm - 1], None
        self.castling, self.ep = u.castling, u.ep
        self.halfmove, self.fullmove = u.halfmove, u.fullmove
        self.turn = self._other(self.turn)

    def push(self, m: Move) -> None:
        """Plays a move that must be legal (check with is_legal first)."""
        self._make(m)
        self._keys.append(self.position_key())

    def pop(self) -> Move:
        self._keys.pop()
        move = self._undo[-1].move
        self._unmake()
        return move

    @property
    def move_stack(self) -> list[Move]:
        return [u.move for u in self._undo]

    # ------------------------------------------------------------------ notation
    def san(self, m: Move) -> str:
        """Standard algebraic notation of a legal move (with + / #)."""
        piece = self.squares[m.frm]
        assert piece is not None
        kind = piece.upper()
        if kind == "K" and abs(m.to - m.frm) == 2:
            text = "O-O" if m.to > m.frm else "O-O-O"
        else:
            capture = self.squares[m.to] is not None or (kind == "P" and m.to == self.ep)
            if kind == "P":
                text = (FILES[m.frm & 7] + "x" if capture else "") + square_name(m.to)
                if m.promotion:
                    text += "=" + m.promotion.upper()
            else:
                others = [o for o in self.legal_moves()
                          if o.to == m.to and o.frm != m.frm and self.squares[o.frm] == piece]
                dis = ""
                if others:
                    same_file = any((o.frm & 7) == (m.frm & 7) for o in others)
                    same_rank = any((o.frm >> 3) == (m.frm >> 3) for o in others)
                    if not same_file:
                        dis = FILES[m.frm & 7]
                    elif not same_rank:
                        dis = str((m.frm >> 3) + 1)
                    else:
                        dis = square_name(m.frm)
                text = kind + dis + ("x" if capture else "") + square_name(m.to)
        self._make(m)
        if self.in_check():
            text += "#" if not self.legal_moves() else "+"
        self._unmake()
        return text

    # ------------------------------------------------------------------ game state
    def _ep_capturable(self) -> bool:
        """En passant counts for repetitions (and FEN) only if a capture is legal."""
        if self.ep is None:
            return False
        return any(m.to == self.ep and self.squares[m.frm] in ("P", "p") for m in self.legal_moves())

    def position_key(self) -> tuple:
        return (tuple(self.squares), self.turn, self.castling,
                self.ep if self._ep_capturable() else None)

    def repetitions(self) -> int:
        """How often the current position has occurred (including now)."""
        return self._keys.count(self._keys[-1])

    def is_checkmate(self) -> bool:
        return self.in_check() and not self.legal_moves()

    def is_stalemate(self) -> bool:
        return not self.in_check() and not self.legal_moves()

    def has_insufficient_material(self, side: str) -> bool:
        """True if ``side`` cannot checkmate by any series of legal moves
        (used for timeouts, FIDE 6.9). Same criteria as the widely used
        python-chess implementation (rewritten here)."""
        own = [p for p in self.squares if p is not None and colour_of(p) == side and p.upper() != "K"]
        theirs = [p for p in self.squares if p is not None and colour_of(p) != side and p.upper() != "K"]
        kinds = {p.upper() for p in own}
        if kinds & {"P", "R", "Q"}:
            return False
        if "N" in kinds:
            # A single knight can only mate with help from enemy pieces other than queens.
            return len(own) <= 1 and all(p.upper() == "Q" for p in theirs)
        if "B" in kinds:
            bishops_on = {((sq & 7) + (sq >> 3)) % 2 for sq, p in enumerate(self.squares)
                          if p is not None and p.upper() == "B"}
            no_pawns_or_knights = not any(p is not None and p.upper() in ("P", "N") for p in self.squares)
            return len(bishops_on) == 1 and no_pawns_or_knights
        return True

    def is_insufficient_material(self) -> bool:
        """Dead position by material: neither side can mate (automatic draw)."""
        return self.has_insufficient_material(WHITE) and self.has_insufficient_material(BLACK)

    def can_claim_threefold(self) -> bool:
        return self.repetitions() >= 3

    def can_claim_fifty_moves(self) -> bool:
        return self.halfmove >= 100

    def automatic_end(self) -> tuple[str, str] | None:
        """(result, termination) if the game is over without a claim, else None.
        Checkmate is tested first: a mating move ends the game even on move 75."""
        if self.is_checkmate():
            return ("0-1" if self.turn == WHITE else "1-0", "checkmate")
        if self.is_stalemate():
            return ("1/2-1/2", "stalemate")
        if self.is_insufficient_material():
            return ("1/2-1/2", "insufficient_material")
        if self.repetitions() >= 5:
            return ("1/2-1/2", "fivefold_repetition")
        if self.halfmove >= 150:
            return ("1/2-1/2", "seventyfive_moves")
        return None


def perft(board: Board, depth: int) -> int:
    """Number of legal move sequences of length ``depth`` (for testing)."""
    moves = board.legal_moves()
    if depth == 1:
        return len(moves)
    total = 0
    for m in moves:
        board._make(m)
        total += perft(board, depth - 1)
        board._unmake()
    return total
