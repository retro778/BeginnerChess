'' =====================================================================
'' BeginnerChess - pgn.bi
'' PGN (Portable Game Notation) import and export.
''
'' Reading understands: tag pairs, move numbers ("12." / "12..."), SAN
'' moves (also with !, ?, +, # marks), comments in { } and after ;,
'' recursive variations ( ... ) (skipped), NAGs ($1), escape lines (%),
'' result tokens, and the SetUp/FEN tags for games from a position.
'' =====================================================================
#pragma once
#include once "game.bi"

Const PGN_MAX_TAGS = 40

Type PgnTags
    count As Integer
    names(0 To PGN_MAX_TAGS - 1) As String
    values(0 To PGN_MAX_TAGS - 1) As String
End Type

Declare Sub Pgn_ClearTags(ByRef t As PgnTags)
Declare Sub Pgn_SetTag(ByRef t As PgnTags, ByRef tagName As Const String, ByRef value As Const String)
Declare Function Pgn_GetTag(ByRef t As PgnTags, ByRef tagName As Const String, _
                            ByRef defaultValue As Const String = "") As String

'' Writes a game as PGN text. Missing Seven-Tag-Roster tags get "?"
'' values; Result, SetUp/FEN and PlyCount are filled in automatically.
Declare Function Pgn_Export(ByRef g As ChessGame, ByRef tags As PgnTags) As String

'' Splits a PGN file's text into one string per game. Returns the count.
Declare Function Pgn_SplitGames(ByRef text As Const String, games() As String) As Integer
'' Parses one game. On failure errMsg says what went wrong and where.
Declare Function Pgn_ParseGame(ByRef gameText As Const String, ByRef g As ChessGame, _
                               ByRef tags As PgnTags, ByRef errMsg As String) As Boolean
'' Reads just the tags of a game (fast; for game lists).
Declare Sub Pgn_ParseTags(ByRef gameText As Const String, ByRef tags As PgnTags)

'' File helpers
Declare Function Pgn_ReadFile(ByRef fileName As Const String, ByRef text As String) As Boolean
Declare Function Pgn_WriteFile(ByRef fileName As Const String, ByRef text As Const String, _
                               ByVal appendMode As Boolean = False) As Boolean
'' Today's date in PGN format "yyyy.mm.dd".
Declare Function Pgn_Today() As String
