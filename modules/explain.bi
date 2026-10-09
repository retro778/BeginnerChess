'' =====================================================================
'' BeginnerChess - explain.bi
'' Friendly, child-level explanations of chess rules: why a move is not
'' allowed, how pieces move. The answers come from asking the rules
'' module (rules.bas); this module never decides legality itself.
'' =====================================================================
#pragma once
#include once "rules.bi"
#include once "notation.bi"

'' Explains why the side to move cannot move the piece on fromSq to toSq.
'' Returns "" if the move is in fact legal.
Declare Function Explain_IllegalMove(ByRef p As Position, ByVal fromSq As Integer, _
                                     ByVal toSq As Integer) As String
'' One-sentence description of how a piece type moves.
Declare Function Explain_HowPieceMoves(ByVal pieceType As Integer) As String
