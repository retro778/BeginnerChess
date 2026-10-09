'' =====================================================================
'' BeginnerChess - career.bas
'' See career.bi.
'' =====================================================================
#include once "career.bi"

Dim Shared CareerList(0 To 6) As Opponent
Dim Shared TierOpp(0 To 2, 0 To 3) As Opponent
Dim Shared Ready As Boolean = False

Private Sub SetOpp(ByRef o As Opponent, ByRef nm As Const String, ByVal rating As Integer, ByVal level As Integer, _
                   ByVal style As Integer, ByVal avatar As Integer, ByRef bio As Const String)
    o.name = nm : o.rating = rating : o.level = level : o.style = style : o.avatar = avatar : o.bio = bio
End Sub

Private Sub InitOpponents()
    If Ready Then Exit Sub
    SetOpp(CareerList(0), "Alex", 600, LEVEL_BEGINNER, STYLE_BALANCED, PT_PAWN, _
           "Alex has just learned how the pieces move. A friendly first opponent!")
    SetOpp(CareerList(1), "Maya", 800, LEVEL_EASY, STYLE_DEFENSIVE, PT_KNIGHT, _
           "Maya likes to keep her pieces safe and is happy with a draw.")
    SetOpp(CareerList(2), "Leo", 1000, LEVEL_EASY, STYLE_BALANCED, PT_BISHOP, _
           "Leo plays solid, sensible chess. Watch your pieces!")
    SetOpp(CareerList(3), "Sophia", 1200, LEVEL_NORMAL, STYLE_POSITIONAL, PT_ROOK, _
           "Sophia loves good pawn structures and active rooks.")
    SetOpp(CareerList(4), "Victor", 1400, LEVEL_NORMAL, STYLE_AGGRESSIVE, PT_QUEEN, _
           "Victor attacks your king at every chance. Defend well!")
    SetOpp(CareerList(5), "Nina", 1500, LEVEL_INTERMEDIATE, STYLE_TACTICAL, PT_KNIGHT, _
           "Nina finds forks and pins everywhere. Look out for tactics!")
    SetOpp(CareerList(6), "The Master", 1700, LEVEL_ADVANCED, STYLE_BALANCED, PT_KING, _
           "The strongest player in the Beginner Chess world. Can you beat the Master?")

    SetOpp(TierOpp(0, 0), "Tom", 450, LEVEL_BEGINNER, STYLE_AGGRESSIVE, PT_PAWN, "Tom loves to attack, even too early.")
    SetOpp(TierOpp(0, 1), "Lily", 550, LEVEL_BEGINNER, STYLE_DEFENSIVE, PT_BISHOP, "Lily is careful and patient.")
    SetOpp(TierOpp(0, 2), "Sam", 650, LEVEL_BEGINNER, STYLE_MATERIAL, PT_ROOK, "Sam grabs every piece he can.")
    SetOpp(TierOpp(0, 3), "Emma", 750, LEVEL_EASY, STYLE_BALANCED, PT_QUEEN, "Emma won last year's Novice Cup.")
    SetOpp(TierOpp(1, 0), "Noah", 900, LEVEL_EASY, STYLE_TACTICAL, PT_KNIGHT, "Noah is a tricky tactician.")
    SetOpp(TierOpp(1, 1), "Mia", 1000, LEVEL_NORMAL, STYLE_DEFENSIVE, PT_BISHOP, "Mia is hard to beat.")
    SetOpp(TierOpp(1, 2), "Ben", 1100, LEVEL_NORMAL, STYLE_AGGRESSIVE, PT_ROOK, "Ben plays for checkmate.")
    SetOpp(TierOpp(1, 3), "Zoe", 1250, LEVEL_NORMAL, STYLE_POSITIONAL, PT_QUEEN, "Zoe is the club champion.")
    SetOpp(TierOpp(2, 0), "Ivan", 1400, LEVEL_INTERMEDIATE, STYLE_POSITIONAL, PT_BISHOP, "Ivan plays like a classical master.")
    SetOpp(TierOpp(2, 1), "Clara", 1500, LEVEL_INTERMEDIATE, STYLE_TACTICAL, PT_KNIGHT, "Clara calculates deeply.")
    SetOpp(TierOpp(2, 2), "Hugo", 1650, LEVEL_ADVANCED, STYLE_DEFENSIVE, PT_ROOK, "Hugo almost never loses.")
    SetOpp(TierOpp(2, 3), "Grandmaster Rex", 1800, LEVEL_ADVANCED, STYLE_AGGRESSIVE, PT_KING, "The favourite to win.")
    Ready = True
End Sub

Function Career_Count() As Integer
    Return 7
End Function

Function Career_Opponent(ByVal i As Integer) As Opponent Ptr
    InitOpponents()
    If i < 0 OrElse i > 6 Then Return 0
    Return @CareerList(i)
End Function

Function Tour_TierCount() As Integer
    Return 3
End Function

Function Tour_TierName(ByVal tier As Integer) As String
    Select Case tier
    Case 0 : Return "Novice Cup"
    Case 1 : Return "Club Championship"
    Case 2 : Return "Masters Invitational"
    End Select
    Return "?"
End Function

Function Tour_Opponent(ByVal tier As Integer, ByVal i As Integer) As Opponent Ptr
    InitOpponents()
    If tier < 0 OrElse tier > 2 OrElse i < 0 OrElse i > 3 Then Return 0
    Return @TierOpp(tier, i)
End Function

'' A tier opens with a high enough rating or after winning the tier below.
Function Tour_TierUnlocked(ByVal tier As Integer) As Boolean
    Dim As PlayerProfile Ptr pr = Profile_Current()
    Select Case tier
    Case 0 : Return True
    Case 1 : Return pr->rating >= 700 OrElse Profile_GetValue("tourwon.0") <> ""
    Case 2 : Return pr->rating >= 1100 OrElse Profile_GetValue("tourwon.1") <> ""
    End Select
    Return False
End Function

Function Tour_TierLockText(ByVal tier As Integer) As String
    Select Case tier
    Case 1 : Return "Win the Novice Cup or reach a rating of 700 to enter."
    Case 2 : Return "Win the Club Championship or reach a rating of 1100 to enter."
    End Select
    Return ""
End Function

'' ---------------------------------------------------------------------
'' State in the profile:
''   tour.tier    active tier (-1 none)
''   tour.res     25 characters: result of row vs column (2/1/0 or "-")
''   tour.next    index of the next player game (0..4; 4 = done)
'' ---------------------------------------------------------------------
Private Function ResString() As String
    Dim As String s = Profile_GetValue("tour.res", "")
    If Len(s) <> TOUR_PLAYERS * TOUR_PLAYERS Then s = String(TOUR_PLAYERS * TOUR_PLAYERS, "-")
    Return s
End Function

Private Sub SetResult(ByVal a As Integer, ByVal b As Integer, ByVal halfPoints As Integer)
    Dim As String s = ResString()
    Mid(s, a * TOUR_PLAYERS + b + 1, 1) = Chr(Asc("0") + halfPoints)
    Mid(s, b * TOUR_PLAYERS + a + 1, 1) = Chr(Asc("0") + (2 - halfPoints))
    Profile_SetValue("tour.res", s)
End Sub

Function Tour_Result(ByVal a As Integer, ByVal b As Integer) As Integer
    Dim As String c = Mid(ResString(), a * TOUR_PLAYERS + b + 1, 1)
    If c = "-" Then Return -1
    Return Asc(c) - Asc("0")
End Function

Function Tour_Active() As Boolean
    Return ValInt(Profile_GetValue("tour.tier", "-1")) >= 0
End Function

Function Tour_ActiveTier() As Integer
    Return ValInt(Profile_GetValue("tour.tier", "-1"))
End Function

Sub Tour_Start(ByVal tier As Integer)
    Profile_SetValue("tour.tier", Str(tier))
    Profile_SetValue("tour.res", String(TOUR_PLAYERS * TOUR_PLAYERS, "-"))
    Profile_SetValue("tour.next", "0")
    Profile_Save()
End Sub

Sub Tour_Abandon()
    Profile_SetValue("tour.tier", "-1")
    Profile_Save()
End Sub

Function Tour_NextOpponent() As Integer
    If Not Tour_Active() Then Return -1
    Dim As Integer n = ValInt(Profile_GetValue("tour.next", "0"))
    If n > 3 Then Return -1
    Return n
End Function

Function Tour_Round() As Integer
    Return ValInt(Profile_GetValue("tour.next", "0")) + 1
End Function

Function Tour_PlayerIsWhite() As Boolean
    Return (ValInt(Profile_GetValue("tour.next", "0")) Mod 2) = 0
End Function

Function Tour_Expected(ByVal ra As Integer, ByVal rb As Integer) As Double
    Return 1 / (1 + 10 ^ ((rb - ra) / 400.0))
End Function

'' Plays a simulated game between computer opponents a and b.
Private Sub SimulateGame(ByVal tier As Integer, ByVal a As Integer, ByVal b As Integer)
    Dim As Double e = Tour_Expected(TierOpp(tier, a).rating, TierOpp(tier, b).rating)
    Dim As Double drawChance = 0.25
    Dim As Double r = Rnd
    Dim As Integer res
    If r < e - drawChance / 2 Then
        res = 2
    ElseIf r < e + drawChance / 2 Then
        res = 1
    Else
        res = 0
    End If
    SetResult(a, b, res)
End Sub

Sub Tour_RecordPlayerResult(ByVal halfPoints As Integer)
    Dim As Integer opp = Tour_NextOpponent()
    If opp < 0 Then Exit Sub
    InitOpponents()
    Dim As Integer tier = Tour_ActiveTier()
    SetResult(TOUR_PLAYER, opp, halfPoints)
    '' The other games of this round: two pairs among the remaining opponents
    '' (each pair of opponents meets once over the 4 rounds; the opponent
    '' who played the player rests). Pairings per round:
    Static pairs(0 To 3, 0 To 3) As Integer = {{1, 2, -1, -1}, {0, 3, 2, 3}, {0, 1, -1, -1}, {0, 2, 1, 3}}
    '' Round 1 (player v 0): 1-2.  Round 2 (v 1): 0-3, 2-3.  Round 3 (v 2): 0-1.  Round 4 (v 3): 0-2, 1-3.
    Dim As Integer k
    For k = 0 To 2 Step 2
        Dim As Integer a = pairs(opp, k), b = pairs(opp, k + 1)
        If a >= 0 AndAlso Tour_Result(a, b) < 0 Then SimulateGame(tier, a, b)
    Next
    Profile_SetValue("tour.next", Str(opp + 1))
    Profile_Save()
End Sub

Function Tour_Score(ByVal i As Integer) As Integer
    Dim As Integer j, s = 0
    For j = 0 To TOUR_PLAYERS - 1
        If j <> i AndAlso Tour_Result(i, j) >= 0 Then s += Tour_Result(i, j)
    Next
    Return s
End Function

Function Tour_Finished() As Boolean
    Return Tour_Active() AndAlso Tour_NextOpponent() < 0
End Function

Function Tour_PlayerPlace() As Integer
    Dim As Integer mine = Tour_Score(TOUR_PLAYER), i, place = 1
    For i = 0 To 3
        If Tour_Score(i) > mine Then place += 1
    Next
    Return place
End Function

Sub Tour_Complete()
    If Not Tour_Finished() Then Exit Sub
    Dim As PlayerProfile Ptr pr = Profile_Current()
    pr->tournamentsPlayed += 1
    If Tour_PlayerPlace() = 1 Then
        pr->tournamentsWon += 1
        Profile_SetValue("tourwon." & Tour_ActiveTier(), "1")
    End If
    Profile_SetValue("tour.tier", "-1")
    Profile_Save()
End Sub
