'' =====================================================================
'' BeginnerChess - famous.bi
'' The Famous Games library, stored in an SQLite database
'' (data/beginnerchess.db in the data folder).
''
'' Tables:
''   meta(key, value)                 content signatures, schema version
''   famous_games(id, white, black, event, site, date, year, result, eco,
''                opening, intro, source, plies, pgn)
''   game_moves(game_id, ply, san, comment)
''   openings(eco, name, moves)       copy of the opening book
''
'' The built-in games come from data/games/famous.pgn; when that file
'' changes, the built-in rows are rebuilt automatically. Games added by
'' the player (source = 'user') are kept. Without SQLite the library is
'' read straight from the PGN file (read-only).
'' =====================================================================
#pragma once
#include once "pgn.bi"

Type FamousGame
    id      As LongInt
    white   As String
    black   As String
    event   As String
    site    As String
    dateStr As String
    year    As Integer
    result  As String
    eco     As String
    opening As String
    intro   As String
    source  As String          '' "builtin" or "user"
    plies   As Integer
    pgn     As String
End Type

'' dbFile: database path. famousPgn: built-in games. bookFile: opening book.
Declare Function Famous_Init(ByRef dbFile As Const String, ByRef famousPgn As Const String, _
                             ByRef bookFile As Const String) As Boolean
Declare Sub Famous_Shutdown()
Declare Function Famous_UsingDatabase() As Boolean
Declare Function Famous_StatusText() As String
Declare Function Famous_Count() As Integer
Declare Function Famous_Get(ByVal index As Integer) As FamousGame Ptr
'' Adds every game of a PGN file to the library (database only).
Declare Function Famous_AddPgnFile(ByRef fileName As Const String, ByRef added As Integer, _
                                   ByRef skipped As Integer, ByRef errMsg As String) As Boolean
'' Removes a game the player added. Built-in games cannot be removed.
Declare Function Famous_Delete(ByVal index As Integer) As Boolean
Declare Function Famous_OpeningCount() As Integer
