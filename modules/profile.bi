'' =====================================================================
'' BeginnerChess - profile.bi
'' Local player profiles: name, statistics, an estimated "BeginnerChess
'' rating", game history and achievements. No internet account needed.
''
'' Each profile is a folder  <data>/profiles/<id>/  containing
''   profile.ini   statistics, rating, achievements, tournament state
''   progress.ini  lessons and puzzles (see progress.bi)
''   history.txt   one line per finished game
''
'' The rating is an Elo-style estimate against BeginnerChess's fictional
'' computer opponents - it is not an official FIDE rating.
'' =====================================================================
#pragma once

Type PlayerProfile
    id             As String
    name           As String
    avatar         As Integer      '' piece type shown as the picture (1..6)
    created        As String
    rating         As Integer
    ratedGames     As Integer
    gamesPlayed    As Integer      '' against the computer
    wins           As Integer
    losses         As Integer
    draws          As Integer
    friendlyGames  As Integer      '' two-player games
    checkmates     As Integer      '' wins by checkmate
    castledGames   As Integer
    promotions     As Integer
    winStreak      As Integer
    bestStreak     As Integer
    bestWinRating  As Integer
    tournamentsPlayed As Integer
    tournamentsWon As Integer
    careerStage    As Integer      '' index of the next career opponent
    famousWatched  As Integer
    bestLevelBeaten As Integer     '' highest engine level beaten (-1 = none)
End Type

'' What happened in a finished game (filled in by the game screen).
Enum GameKind
    GK_FREE = 0         '' casual game against the computer
    GK_TWO_PLAYER
    GK_CAREER
    GK_TOURNAMENT
End Enum

Type GameRecord
    kind        As Integer
    opponent    As String
    oppRating   As Integer
    score       As Single     '' for the player: 1 win, 0.5 draw, 0 loss
    byMate      As Boolean    '' the player checkmated the opponent
    castled     As Boolean    '' the player castled
    promoted    As Boolean    '' the player promoted a pawn
    rated       As Boolean    '' counts for the rating (no take-backs)
    plies       As Integer
    level       As Integer    '' engine level of the opponent
End Type

Declare Sub Profile_Init(ByRef dataDir As Const String, ByRef preferredId As Const String)
Declare Function Profile_Current() As PlayerProfile Ptr
Declare Function Profile_Dir() As String
Declare Sub Profile_Save()

Declare Function Profile_Count() As Integer
Declare Function Profile_IdAt(ByVal index As Integer) As String
Declare Function Profile_NameOf(ByRef id As Const String) As String
Declare Function Profile_Create(ByRef playerName As Const String) As String
Declare Function Profile_Select(ByRef id As Const String) As Boolean
Declare Function Profile_Rename(ByRef playerName As Const String) As Boolean
Declare Function Profile_Delete(ByRef id As Const String) As Boolean

'' Records a finished game; returns the rating change (0 if unrated).
Declare Function Profile_RecordGame(ByRef rec As GameRecord) As Integer
Declare Function Profile_RatingChange(ByVal rating As Integer, ByVal oppRating As Integer, _
                                      ByVal score As Single, ByVal ratedGames As Integer) As Integer
Declare Function Profile_RankTitle(ByVal rating As Integer) As String
'' Last n history lines, newest first: "date|kind|opponent|rating|W/D/L|ratingAfter|change"
Declare Function Profile_History(lines() As String, ByVal maxLines As Integer) As Integer
Declare Function Profile_WinPercent() As Integer

'' Extra key/value data in profile.ini (used by tournaments).
Declare Function Profile_GetValue(ByRef key As Const String, ByRef def As Const String = "") As String
Declare Sub Profile_SetValue(ByRef key As Const String, ByRef value As Const String)

'' ---- Achievements ---------------------------------------------------
Declare Function Ach_Count() As Integer
Declare Function Ach_Id(ByVal i As Integer) As String
Declare Function Ach_Title(ByVal i As Integer) As String
Declare Function Ach_Description(ByVal i As Integer) As String
Declare Function Ach_Unlocked(ByVal i As Integer) As Boolean
Declare Function Ach_UnlockedCount() As Integer
'' Checks every achievement against the profile/progress and unlocks the
'' newly earned ones. Returns their titles separated by "|" ("" = none).
'' lessonTotal/puzzleTotal: size of the course; forkTotal: fork puzzles.
Declare Function Ach_CheckAll(ByVal lessonTotal As Integer, ByVal puzzleTotal As Integer, _
                              ByVal chapter1Done As Boolean, ByVal forkDone As Boolean, _
                              ByVal careerTotal As Integer) As String
