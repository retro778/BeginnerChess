'' =====================================================================
'' BeginnerChess - tests/test_profile.bas
'' Tests for player profiles, rating, achievements, career and tournaments.
'' =====================================================================
#include once "../modules/career.bi"
#include once "testutil.bi"
#include once "../modules/progress.bi"

Dim Shared TestsPassed As Integer = 0
Dim Shared TestsFailed As Integer = 0

Sub Check(ByVal ok As Boolean, ByRef testName As Const String, ByRef detail As Const String = "")
    If ok Then
        TestsPassed += 1
    Else
        TestsFailed += 1
        Print "  FAIL: " & testName;
        If detail <> "" Then Print "  (" & detail & ")" Else Print
    End If
End Sub

Dim Shared TMP As String
TMP = Test_TempDir("cm_test_profile")

Function Game(ByVal kind As Integer, ByVal score As Single, ByVal oppRating As Integer, ByVal level As Integer, _
              ByVal mate As Boolean = False, ByVal rated As Boolean = True) As Integer
    Dim As GameRecord r
    r.kind = kind : r.opponent = "Test" : r.oppRating = oppRating : r.score = score
    r.byMate = mate : r.rated = rated : r.level = level : r.plies = 40
    Return Profile_RecordGame(r)
End Function

Sub TestProfiles()
    Print "Profiles..."
    Test_RemoveTree(TMP)
    Test_MakeDirs(TMP)
    Profile_Init(TMP, "")
    Check Profile_Count() = 1 AndAlso Profile_Current()->name = "Player", "a default profile is created"
    Check Profile_Current()->rating = 400, "starting rating 400"
    Dim As String id2 = Profile_Create("Dana")
    Check Profile_Count() = 2 AndAlso Profile_Current()->name = "Dana", "second profile created and selected"
    Progress_SetPuzzleSolved("m1-01") : Progress_Save()
    Profile_Select(Profile_IdAt(0))
    Check Progress_PuzzlesSolved() = 0, "progress belongs to each profile"
    Profile_Select(id2)
    Check Progress_PuzzlesSolved() = 1, "switching back restores progress"
    Check Profile_Rename("Dana R.") AndAlso Profile_NameOf(id2) = "Dana R.", "rename"
End Sub

Sub TestRating()
    Print "Statistics and rating..."
    Check Profile_RatingChange(1000, 1000, 1, 0) = 20, "even game won: +20 (new player)", Str(Profile_RatingChange(1000, 1000, 1, 0))
    Check Profile_RatingChange(1000, 1000, 0, 30) = -12, "even game lost: -12 (experienced)"
    Check Profile_RatingChange(600, 1400, 1, 0) > 35, "beating a much stronger opponent gives a lot"
    Dim As Integer before = Profile_Current()->rating
    Dim As Integer ch = Game(GK_FREE, 1, 400, LEVEL_BEGINNER, True)
    Check Profile_Current()->rating = before + ch AndAlso ch = 20, "rated win changes the rating", Str(ch)
    Game(GK_FREE, 0.5, 800, LEVEL_EASY)
    Game(GK_FREE, 0, 800, LEVEL_EASY)
    Check Game(GK_FREE, 1, 800, LEVEL_EASY, False, False) = 0, "unrated game (take-backs) keeps the rating"
    Game(GK_TWO_PLAYER, 1, 0, 0)
    Dim As PlayerProfile Ptr p = Profile_Current()
    Check p->gamesPlayed = 4 AndAlso p->wins = 2 AndAlso p->draws = 1 AndAlso p->losses = 1, "game counters", _
          p->gamesPlayed & " " & p->wins & " " & p->draws & " " & p->losses
    Check p->friendlyGames = 1, "two-player game counted separately"
    Check p->checkmates = 1, "checkmates counted"
    Check Profile_WinPercent() = 63, "win percentage", Str(Profile_WinPercent())
    Dim As String lines()
    Dim As Integer n = Profile_History(lines(), 3)
    Check n = 3 AndAlso InStr(lines(0), "|Two players|") > 0, "history newest first", lines(0)
    Check Profile_RankTitle(450) = "Beginner" AndAlso Profile_RankTitle(1250) = "Expert", "rank titles"
End Sub

Sub TestAchievements()
    Print "Achievements..."
    Dim As String newly = Ach_CheckAll(68, 44, False, False, 7)
    Check InStr(newly, "First Game") > 0 AndAlso InStr(newly, "First Victory") > 0 AndAlso _
          InStr(newly, "First Checkmate") > 0 AndAlso InStr(newly, "Puzzle Solver") > 0, "earned achievements unlock", newly
    Check Ach_CheckAll(68, 44, False, False, 7) = "", "achievements unlock only once"
    Check InStr(newly, "Hat Trick") = 0, "not yet a hat trick"
    Game(GK_FREE, 1, 800, LEVEL_NORMAL)
    Game(GK_FREE, 1, 800, LEVEL_NORMAL)
    Dim As GameRecord r
    r.kind = GK_FREE : r.score = 1 : r.oppRating = 800 : r.level = LEVEL_NORMAL : r.promoted = True : r.rated = True
    Profile_RecordGame(r)
    newly = Ach_CheckAll(68, 44, False, False, 7)
    Check InStr(newly, "Hat Trick") > 0 AndAlso InStr(newly, "Strong Opponent") > 0 AndAlso InStr(newly, "New Queen") > 0, _
          "streak, level and promotion achievements", newly
    Check Ach_UnlockedCount() >= 7, "unlocked count", Str(Ach_UnlockedCount())
    '' Survives a restart
    Dim As String id = Profile_Current()->id
    Profile_Init(TMP, id)
    Check Ach_UnlockedCount() >= 7 AndAlso Profile_Current()->gamesPlayed = 7, "profile reloads", Str(Profile_Current()->gamesPlayed)
End Sub

Sub TestCareerAndTournament()
    Print "Career and tournaments..."
    Dim As Integer i, ascending = -1
    For i = 1 To Career_Count() - 1
        If Career_Opponent(i)->rating <= Career_Opponent(i - 1)->rating Then ascending = 0
    Next
    Check Career_Count() = 7 AndAlso ascending <> 0, "career ladder of 7 rising opponents"
    Check Career_Opponent(0)->name = "Alex" AndAlso Career_Opponent(0)->rating = 600, "Alex 600 first"
    Check Abs(Tour_Expected(1000, 1000) - 0.5) < 0.001, "equal ratings expect 50%"

    Profile_Create("Tourney")
    Check Tour_TierUnlocked(0) AndAlso Not Tour_TierUnlocked(1), "only the Novice Cup is open at first"
    Randomize 42
    Tour_Start(0)
    Check Tour_Active() AndAlso CBool(Tour_NextOpponent() = 0) AndAlso Tour_PlayerIsWhite(), "tournament starts with White v opponent 1"
    Dim As Integer results(0 To 3) = {2, 2, 1, 2}
    For i = 0 To 3
        Tour_RecordPlayerResult(results(i))
        If i = 0 Then Check Not Tour_PlayerIsWhite(), "colours alternate"
    Next
    Check Tour_Finished(), "tournament finished after 4 games"
    Dim As Integer total = 0, played = 0, a, b
    For i = 0 To TOUR_PLAYERS - 1
        total += Tour_Score(i)
    Next
    For a = 0 To 4
        For b = a + 1 To 4
            If Tour_Result(a, b) >= 0 Then played += 1
        Next
    Next
    Check played = 10, "every pair has played once", Str(played)
    Check total = 20, "half points add up (10 games)", Str(total)
    Check Tour_Score(TOUR_PLAYER) = 7, "player scored 3.5 / 4"
    Dim As Integer place = Tour_PlayerPlace()
    Tour_Complete()
    Check Not Tour_Active() AndAlso Profile_Current()->tournamentsPlayed = 1, "tournament closed"
    If place = 1 Then
        Check Profile_Current()->tournamentsWon = 1 AndAlso Tour_TierUnlocked(1), "winning opens the next tier"
    End If
    '' Abandon
    Tour_Start(0)
    Tour_RecordPlayerResult(0)
    Tour_Abandon()
    Check Not Tour_Active(), "a tournament can be abandoned"
    Check Profile_Delete(Profile_Current()->id) AndAlso Profile_Count() = 2, "delete a profile"
    Test_RemoveTree(TMP)
End Sub

Print "BeginnerChess profile and tournament tests"
TestProfiles()
TestRating()
TestAchievements()
TestCareerAndTournament()
Print
Print "Passed: " & TestsPassed & "   Failed: " & TestsFailed
If TestsFailed > 0 Then End 1
End 0
