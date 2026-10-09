'' =====================================================================
'' BeginnerChess - notation.bi
'' Converting moves to and from text:
''   SAN  (Standard Algebraic Notation, e.g. "Nf3", "exd5", "O-O", "e8=Q+")
''   UCI  (coordinate notation, e.g. "g1f3", "e7e8q")
'' =====================================================================
#pragma once
#include once "rules.bi"

'' SAN for a legal move in position p (p is used temporarily but is
'' returned unchanged). Includes "+" / "#" suffixes.
Declare Function Notation_MoveToSAN(ByRef p As Position, ByRef m As ChessMove) As String

'' Coordinate notation, e.g. "e2e4", "a7a8q".
Declare Function Notation_MoveToUCI(ByRef m As ChessMove) As String

'' Parses SAN (lenient: accepts "0-0", missing "x", "e8Q", "+"/"#"/"!"/"?"
'' annotations, lowercase piece letters except 'b'). On failure returns
'' False and a friendly explanation in errMsg.
Declare Function Notation_ParseSAN(ByRef p As Position, ByRef text As Const String, _
                                   ByRef outMove As ChessMove, ByRef errMsg As String) As Boolean

Declare Function Notation_ParseUCI(ByRef p As Position, ByRef text As Const String, _
                                   ByRef outMove As ChessMove, ByRef errMsg As String) As Boolean

'' Accepts either SAN or coordinate notation.
Declare Function Notation_ParseMove(ByRef p As Position, ByRef text As Const String, _
                                    ByRef outMove As ChessMove, ByRef errMsg As String) As Boolean

'' Piece names for friendly messages, e.g. "knight".
Declare Function Notation_PieceName(ByVal pieceType As Integer) As String
