'' =====================================================================
'' BeginnerChess - analysis.bi
'' Post-game review: the engine looks at every position of a game and
'' classifies each move as Best / Good / Inaccuracy / Mistake / Blunder
'' by how much it changed the mover's chances of winning. These are
'' educational estimates from BeginnerChess's own engine, not the verdict
'' of a professional engine.
''
'' The work is done in small steps (one position per call), so a screen
'' can show progress and stay responsive.
'' =====================================================================
#pragma once
#include once "game.bi"
#include once "engine.bi"

Enum MoveClass
    MC_BEST = 0
    MC_GOOD
    MC_INACCURACY
    MC_MISTAKE
    MC_BLUNDER
    MC_BOOK          '' opening book move (not judged)
End Enum

Type PositionInfo
    score    As Integer      '' best score for the side to move (centipawns)
    bestMove As ChessMove
    terminal As Boolean      '' no legal move (mate or stalemate)
    whiteScore As Integer    '' the same score from White's point of view (clamped)
End Type

Declare Sub Analysis_Begin(ByRef g As ChessGame, ByVal msPerPosition As Integer = 250)
'' Analyses the next position. Returns True when everything is done.
Declare Function Analysis_Step() As Boolean
Declare Function Analysis_Progress() As Integer        '' 0..100
Declare Function Analysis_Done() As Boolean
Declare Function Analysis_Plies() As Integer

'' Results for ply i (the move g.sanMoves(i)):
Declare Function Analysis_Class(ByVal i As Integer) As Integer
Declare Function Analysis_Loss(ByVal i As Integer) As Integer   '' lost winning chance, % points
Declare Function Analysis_BestMove(ByVal i As Integer) As ChessMove
Declare Function Analysis_PlayedMove(ByVal i As Integer) As ChessMove
'' Score after ply i (i = -1: start), from White's point of view.
Declare Function Analysis_WhiteScore(ByVal i As Integer) As Integer
'' Position before ply i.
Declare Sub Analysis_PositionBefore(ByVal i As Integer, ByRef p As Position)
Declare Function Analysis_ClassName(ByVal c As Integer) As String
'' Winning chance (0..100) for a score in centipawns.
Declare Function Analysis_WinChance(ByVal score As Integer) As Double
'' Classification from a loss of winning chance (% points).
Declare Function Analysis_Classify(ByVal loss As Double, ByVal isBest As Boolean) As Integer
