'' =====================================================================
'' BeginnerChess - openings.bi
'' Opening book: named opening lines loaded from a text file
'' (data/openings/book.txt). Used by the engine for varied, sensible
'' opening moves and by the GUI to show the name of the opening played.
'' =====================================================================
#pragma once
#include once "notation.bi"

'' Loads the book. Returns the number of lines loaded; badLines counts
'' lines that could not be read (firstError describes the first one).
Declare Function Book_Load(ByRef fileName As Const String, ByRef badLines As Integer, _
                           ByRef firstError As String) As Integer
Declare Sub Book_Clear()
Declare Function Book_IsLoaded() As Boolean
'' Picks a book move for p. r (0 <= r < 1) selects among the candidates,
'' weighted by how many book lines play each move.
Declare Function Book_Probe(ByRef p As Position, ByVal r As Double, ByRef m As ChessMove) As Boolean
'' Number of distinct book moves in position p.
Declare Function Book_MoveCount(ByRef p As Position) As Integer
'' Name of the opening reached in this game, e.g. "C50 Italian Game";
'' "" if the game did not start with a known line.
Declare Function Book_OpeningName(ByRef p As Position) As String
Declare Function Book_OpeningEco(ByRef p As Position) As String
