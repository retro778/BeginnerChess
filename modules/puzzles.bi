'' =====================================================================
'' BeginnerChess - puzzles.bi
'' Chess puzzles (exercises), loaded from data/puzzles/*.txt.
''
'' File format:
''   PUZZLE <id>
''   TITLE <text>
''   CATEGORY <text>          e.g. "Mate in one", "Fork", "Endgame"
''   LEVEL <1..5>             difficulty
''   FEN <fen>                the side to move is the player
''   MOVES <SAN ...>          solution: player, reply, player, ...
''   ACCEPT <SAN ...>         other first moves that also count as correct
''                            (only for one-move puzzles)
''   HINT <text>
''   EXPLAIN <text>           shown after solving ("|" = new line)
''   END
'' Any move that gives checkmate is always accepted.
'' =====================================================================
#pragma once
#include once "game.bi"

Type Puzzle
    id       As String
    title    As String
    category As String
    level    As Integer
    fen      As String
    moves    As String          '' solution line (SAN, space separated)
    accept   As String
    hint     As String
    explain  As String
End Type

Declare Function Puzzles_LoadFolder(ByRef folder As Const String, ByRef errors As String) As Integer
Declare Function Puzzles_Count() As Integer
Declare Function Puzzles_Get(ByVal index As Integer) As Puzzle Ptr
Declare Function Puzzles_Find(ByRef id As Const String) As Integer
Declare Function Puzzles_CategoryCount() As Integer
Declare Function Puzzles_CategoryName(ByVal index As Integer) As String

'' Number of moves in the solution line and the k-th one (0-based).
Declare Function Puzzle_MoveCount(ByRef pz As Puzzle) As Integer
Declare Function Puzzle_Move(ByRef pz As Puzzle, ByVal k As Integer) As String
'' Number of moves the player has to find.
Declare Function Puzzle_PlayerMoves(ByRef pz As Puzzle) As Integer

Enum PuzzleVerdict
    PV_WRONG = 0
    PV_CORRECT          '' right move, puzzle continues
    PV_SOLVED           '' puzzle complete
End Enum

'' Judges the player's move m (legal in p) at solution index k.
Declare Function Puzzle_Judge(ByRef pz As Puzzle, ByVal k As Integer, ByRef p As Position, _
                              ByRef m As ChessMove) As Integer
'' Instruction line, e.g. "White to move - checkmate in one move!".
Declare Function Puzzle_Instruction(ByRef pz As Puzzle, ByVal sideToMove As Integer) As String
