'' =====================================================================
'' BeginnerChess - savegame.bi
'' Saving and loading unfinished (or finished) games in save slots.
''
'' A save file is an ordinary PGN file (it can be opened by any chess
'' program) with extra "CM..." tags holding BeginnerChess's settings:
'' opponent, level, style, the player's side, board orientation and the
'' exact final position (CMFEN) used to detect damaged files. Replaying
'' the moves restores everything else: castling rights, en passant,
'' move counters and the history needed for repetition draws.
'' =====================================================================
#pragma once
#include once "pgn.bi"

Const SAVE_SLOTS = 8          '' manual slots 1..8; slot 0 = autosave

Type SaveSetup
    opponent   As Integer      '' 0 = two players, 1 = computer
    playAs     As Integer      '' 0 White, 1 Black, 2 Random (as chosen)
    difficulty As Integer
    style      As Integer
    humanSide  As Integer
    flipped    As Boolean
    practice   As Boolean      '' practice game (hints, take-backs)
End Type

Type SaveInfo
    exists      As Boolean
    valid       As Boolean
    description As String      '' e.g. "You vs Computer (Normal)"
    savedAt     As String      '' "2026.10.07 21:30"
    moveCount   As Integer
    result      As String
    errorText   As String
End Type

Declare Sub Save_SetDirectory(ByRef path As Const String)
Declare Function Save_Directory() As String
Declare Function Save_EnsureDirectory() As Boolean
Declare Function Save_SlotFile(ByVal slot As Integer) As String
Declare Function Save_SlotName(ByVal slot As Integer) As String
Declare Function Save_Write(ByVal slot As Integer, ByRef g As ChessGame, ByRef setup As SaveSetup, _
                            ByRef errMsg As String) As Boolean
Declare Function Save_Read(ByVal slot As Integer, ByRef g As ChessGame, ByRef setup As SaveSetup, _
                           ByRef errMsg As String) As Boolean
Declare Function Save_ReadInfo(ByVal slot As Integer, ByRef info As SaveInfo) As Boolean
Declare Function Save_Delete(ByVal slot As Integer) As Boolean
'' Names used in PGN headers for the two players.
Declare Function Save_PlayerName(ByRef setup As SaveSetup, ByVal side As Integer) As String
