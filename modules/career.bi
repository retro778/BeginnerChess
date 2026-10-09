'' =====================================================================
'' BeginnerChess - career.bi
'' Career ladder and tournaments against fictional computer opponents.
'' The ratings are BeginnerChess estimates, not official FIDE ratings.
''
'' Career: beat each opponent of the ladder to unlock the next one.
'' Tournaments: a round robin of the player and 4 computer opponents;
'' the player meets each opponent once (colours alternate), the games
'' between the computer opponents are simulated from their ratings.
'' The state is stored in the player's profile, so a tournament can be
'' continued another day.
'' =====================================================================
#pragma once
#include once "engine.bi"
#include once "profile.bi"

Type Opponent
    name    As String
    rating  As Integer
    level   As Integer        '' EngineLevel
    style   As Integer        '' EngineStyle
    avatar  As Integer        '' piece type used as picture
    bio     As String
End Type

Const TOUR_PLAYERS = 5        '' 4 opponents + the player (index 4)
Const TOUR_PLAYER = 4

Declare Function Career_Count() As Integer
Declare Function Career_Opponent(ByVal i As Integer) As Opponent Ptr

Declare Function Tour_TierCount() As Integer
Declare Function Tour_TierName(ByVal tier As Integer) As String
Declare Function Tour_TierUnlocked(ByVal tier As Integer) As Boolean
Declare Function Tour_TierLockText(ByVal tier As Integer) As String
Declare Function Tour_Opponent(ByVal tier As Integer, ByVal i As Integer) As Opponent Ptr

'' Tournament state (kept in the current profile)
Declare Function Tour_Active() As Boolean
Declare Function Tour_ActiveTier() As Integer
Declare Sub Tour_Start(ByVal tier As Integer)
Declare Sub Tour_Abandon()
'' Opponent (0..3) the player meets next, or -1 when the tournament is over.
Declare Function Tour_NextOpponent() As Integer
Declare Function Tour_Round() As Integer          '' 1-based round number of the next game
Declare Function Tour_PlayerIsWhite() As Boolean  '' colour in the next game
'' Records the player's result (2 = win, 1 = draw, 0 = loss) against the
'' next opponent and simulates the other games of that round.
Declare Sub Tour_RecordPlayerResult(ByVal halfPoints As Integer)
'' Score in half points for participant i (0..3 opponents, 4 = player).
Declare Function Tour_Score(ByVal i As Integer) As Integer
'' Result of the game between participants a and b for a (2/1/0) or -1.
Declare Function Tour_Result(ByVal a As Integer, ByVal b As Integer) As Integer
Declare Function Tour_Finished() As Boolean
'' Final place of the player (1 = winner; ties count in the player's favour).
Declare Function Tour_PlayerPlace() As Integer
'' Closes a finished tournament: updates the profile statistics.
Declare Sub Tour_Complete()

'' For testing the simulation: expected score of a against b.
Declare Function Tour_Expected(ByVal ra As Integer, ByVal rb As Integer) As Double
