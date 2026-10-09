'' =====================================================================
'' BeginnerChess - coach.bi
'' Turns chess facts into child-friendly explanations:
''   * static exchange evaluation (who wins a fight over a square),
''   * threatened pieces,
''   * why a move is good ("Your bishop is attacked - moving it saves it",
''     "Fork! Your knight attacks the king and the rook", ...),
''   * what the opponent threatens after a mistake,
''   * evaluation in words ("White is better by about two pawns").
'' The explanations are heuristic teaching aids, not proofs.
'' =====================================================================
#pragma once
#include once "engine.bi"
#include once "notation.bi"

'' Material gained by the side making capture m (centipawns, may be <0).
Declare Function Coach_SEE(ByRef p As Position, ByRef m As ChessMove) As Integer
'' Best material the side NOT owning the piece on sq could win there
'' (0 = the piece is safe). Used for "threatened" pieces.
Declare Function Coach_ThreatOn(ByRef p As Position, ByVal sq As Integer) As Integer
'' Marks threatened pieces of 'side' (value > 0 in result(sq)).
Declare Sub Coach_ThreatenedPieces(ByRef p As Position, ByVal side As Integer, result() As Integer)
'' Why move m (legal in p) is a good move, from the mover's point of view.
Declare Function Coach_ExplainMove(ByRef p As Position, ByRef m As ChessMove) As String
'' What the opponent can do with reply r (legal in p, opponent to move).
Declare Function Coach_ExplainThreat(ByRef p As Position, ByRef r As ChessMove) As String
'' Evaluation in words; score in centipawns from White's point of view.
Declare Function Coach_EvalText(ByVal whiteScore As Integer) As String
'' Piece value used by the coach (pawn 100 ... queen 900, king 10000).
Declare Function Coach_PieceValue(ByVal pieceType As Integer) As Integer
