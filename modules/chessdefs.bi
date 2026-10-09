'' =====================================================================
'' BeginnerChess - chessdefs.bi
'' Shared constants and core data types used by every chess module.
''
'' Board representation: "0x88" mailbox.
''   The board is an array of 128 bytes. Square index = rank * 16 + file,
''   where file 0..7 = a..h and rank 0..7 = 1..8. Only the left half of
''   each 16-square row is a real square; a square index is off the board
''   whenever (index And &h88) <> 0. This makes edge detection for piece
''   movement a single bit test.
'' =====================================================================
#pragma once

#define CM_VERSION "2.0.0"

'' ---------------------------------------------------------------------
'' Sides
'' ---------------------------------------------------------------------
Const SIDE_WHITE = 0
Const SIDE_BLACK = 1

'' ---------------------------------------------------------------------
'' Piece types (low 3 bits of a piece code)
'' ---------------------------------------------------------------------
Const PT_NONE   = 0
Const PT_PAWN   = 1
Const PT_KNIGHT = 2
Const PT_BISHOP = 3
Const PT_ROOK   = 4
Const PT_QUEEN  = 5
Const PT_KING   = 6

'' ---------------------------------------------------------------------
'' Piece codes: colour * 8 + type. 0 = empty square.
'' ---------------------------------------------------------------------
Const PC_EMPTY = 0
Const PC_WP = 1, PC_WN = 2, PC_WB = 3, PC_WR = 4, PC_WQ = 5, PC_WK = 6
Const PC_BP = 9, PC_BN = 10, PC_BB = 11, PC_BR = 12, PC_BQ = 13, PC_BK = 14

#define PIECE_TYPE(pc)        ((pc) And 7)
#define PIECE_COLOR(pc)       ((pc) Shr 3)
#define MAKE_PIECE(side, pt)  (((side) Shl 3) Or (pt))

'' ---------------------------------------------------------------------
'' Squares
'' ---------------------------------------------------------------------
Const NO_SQUARE = -1

#define MAKE_SQ(file, rank)    ((rank) * 16 + (file))
#define SQ_FILE(s)        ((s) And 7)
#define SQ_RANK(s)        ((s) Shr 4)
#define SQ_OFFBOARD(s)    (((s) And &h88) <> 0)

Const SQ_A1 = 0,   SQ_B1 = 1,   SQ_C1 = 2,   SQ_D1 = 3
Const SQ_E1 = 4,   SQ_F1 = 5,   SQ_G1 = 6,   SQ_H1 = 7
Const SQ_A8 = 112, SQ_B8 = 113, SQ_C8 = 114, SQ_D8 = 115
Const SQ_E8 = 116, SQ_F8 = 117, SQ_G8 = 118, SQ_H8 = 119

'' ---------------------------------------------------------------------
'' Castling rights (bit flags)
'' ---------------------------------------------------------------------
Const CR_WHITE_KING  = 1
Const CR_WHITE_QUEEN = 2
Const CR_BLACK_KING  = 4
Const CR_BLACK_QUEEN = 8

'' ---------------------------------------------------------------------
'' Move flags (bit flags)
'' ---------------------------------------------------------------------
Const MF_CAPTURE     = 1
Const MF_DOUBLE_PUSH = 2
Const MF_EN_PASSANT  = 4
Const MF_CASTLE      = 8
Const MF_PROMOTION   = 16

'' A single chess move. Moves carry enough information to be undone.
Type ChessMove
    fromSq    As UByte    '' 0x88 square the piece leaves
    toSq      As UByte    '' 0x88 square the piece arrives on
    piece     As UByte    '' piece code that moves
    captured  As UByte    '' piece code captured (PC_EMPTY if none)
    promotion As UByte    '' piece TYPE promoted to (PT_NONE if none)
    flags     As UByte    '' MF_* flags
End Type

'' Maximum number of moves in any chess position is 218; 256 is safe.
Const MAX_MOVES = 256

Type MoveList
    count As Integer
    moves(0 To MAX_MOVES - 1) As ChessMove
End Type

'' Maximum number of half-moves (plies) a position can remember for
'' undo and repetition detection. Includes room for engine search depth.
Const MAX_HISTORY = 2048

'' Information needed to undo a move.
Type UndoInfo
    mv        As ChessMove
    castling  As Integer
    epSquare  As Integer
    halfmove  As Integer
    hash      As ULongInt    '' hash of the position BEFORE the move
End Type

'' The complete state of a chess position, plus the undo stack.
Type Position
    board(0 To 127) As UByte     '' piece codes on 0x88 squares
    sideToMove      As Integer   '' SIDE_WHITE / SIDE_BLACK
    castling        As Integer   '' CR_* flags
    epSquare        As Integer   '' en-passant target square or NO_SQUARE
    halfmoveClock   As Integer   '' plies since last capture / pawn move
    fullmoveNumber  As Integer   '' starts at 1, increments after Black moves
    kingSq(0 To 1)  As Integer   '' king location for each side
    hash            As ULongInt  '' Zobrist hash of the position
    historyCount    As Integer   '' number of entries on the undo stack
    undoStack(0 To MAX_HISTORY - 1) As UndoInfo
End Type

#define START_FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
