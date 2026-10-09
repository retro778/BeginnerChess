'' =====================================================================
'' BeginnerChess - rules.bi
'' The chess rules: position setup, FEN, move generation, making and
'' unmaking moves, attack detection, and draw-rule helpers.
''
'' This module knows nothing about graphics, sound or the user. Every
'' other system (GUI, engine, lessons, PGN...) asks this module whether
'' a move is legal.
'' =====================================================================
#pragma once
#include once "chessdefs.bi"

'' One-time initialisation (Zobrist keys, lookup tables). Safe to call
'' more than once. Every Pos_* routine calls it automatically if needed.
Declare Sub Rules_Init()

'' ---- Position setup -------------------------------------------------
Declare Sub Pos_Clear(ByRef p As Position)
Declare Sub Pos_SetStart(ByRef p As Position)
Declare Function Pos_LoadFEN(ByRef p As Position, ByRef fen As Const String, _
                             ByRef errMsg As String) As Boolean
Declare Function Pos_GetFEN(ByRef p As Position) As String
Declare Function Pos_ComputeHash(ByRef p As Position) As ULongInt

'' ---- Attacks and check ----------------------------------------------
Declare Function Pos_IsSquareAttacked(ByRef p As Position, ByVal sq As Integer, _
                                      ByVal bySide As Integer) As Boolean
Declare Function Pos_InCheck(ByRef p As Position) As Boolean
Declare Function Pos_CountCheckers(ByRef p As Position) As Integer

'' ---- Move generation ------------------------------------------------
'' Pseudo-legal moves may leave the mover's own king in check.
Declare Sub Pos_GeneratePseudo(ByRef p As Position, ByRef list As MoveList)
'' Legal moves only.
Declare Sub Pos_GenerateLegal(ByRef p As Position, ByRef list As MoveList)
Declare Function Pos_HasLegalMove(ByRef p As Position) As Boolean

'' Looks up the legal move matching from/to/promotion. promoType may be
'' PT_NONE for non-promotions. Returns False if no such legal move.
Declare Function Pos_FindLegalMove(ByRef p As Position, ByVal fromSq As Integer, _
                                   ByVal toSq As Integer, ByVal promoType As Integer, _
                                   ByRef outMove As ChessMove) As Boolean

'' ---- Making moves ---------------------------------------------------
'' Pos_MakeMove does NOT check legality; only pass moves produced by the
'' generator. Returns False only if the undo stack is full.
Declare Function Pos_MakeMove(ByRef p As Position, ByRef m As ChessMove) As Boolean
Declare Sub Pos_UnmakeMove(ByRef p As Position)
'' "Null move": the side to move passes (used by the engine's null-move
'' pruning; never legal in a real game). Undo it with Pos_UnmakeMove.
Declare Function Pos_MakeNullMove(ByRef p As Position) As Boolean
'' True if the side that just moved left its own king in check.
Declare Function Pos_LastMoveWasIllegal(ByRef p As Position) As Boolean

'' ---- Draw rules -----------------------------------------------------
'' How many times the current position has occurred (including now).
Declare Function Pos_RepetitionCount(ByRef p As Position) As Integer
Declare Function Pos_IsInsufficientMaterial(ByRef p As Position) As Boolean

'' ---- Testing --------------------------------------------------------
Declare Function Pos_Perft(ByRef p As Position, ByVal depth As Integer) As ULongInt

'' ---- Small helpers --------------------------------------------------
Declare Function Sq_Name(ByVal sq As Integer) As String
Declare Function Sq_Parse(ByRef s As Const String) As Integer
Declare Function Piece_Char(ByVal pc As Integer) As String     '' FEN letter
Declare Function Move_IsNull(ByRef m As ChessMove) As Boolean
Declare Function Move_Equal(ByRef a As ChessMove, ByRef b As ChessMove) As Boolean
