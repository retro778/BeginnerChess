'' =====================================================================
'' BeginnerChess - profile.bas
'' See profile.bi.
'' =====================================================================
#include once "profile.bi"
#include once "progress.bi"
#include once "file.bi"
#include once "dir.bi"

Dim Shared ProfilesDir As String
Dim Shared Cur As PlayerProfile
Dim Shared ExtraKeys() As String
Dim Shared ExtraValues() As String
Dim Shared ExtraCount As Integer = 0
Dim Shared IdList(0 To 63) As String
Dim Shared IdCount As Integer = 0

'' ---------------------------------------------------------------------
'' Storage
'' ---------------------------------------------------------------------
Private Sub ScanProfiles()
    IdCount = 0
    Dim As String d = Dir(ProfilesDir & "/*", fbDirectory)
    Do While d <> "" AndAlso IdCount < 64
        If d <> "." AndAlso d <> ".." AndAlso FileExists(ProfilesDir & "/" & d & "/profile.ini") Then
            IdList(IdCount) = d
            IdCount += 1
        End If
        d = Dir()
    Loop
    '' Sort for a stable order.
    Dim As Integer i, j
    For i = 0 To IdCount - 2
        For j = i + 1 To IdCount - 1
            If IdList(j) < IdList(i) Then Swap IdList(i), IdList(j)
        Next
    Next
End Sub

Function Profile_GetValue(ByRef key As Const String, ByRef def As Const String = "") As String
    Dim As Integer i
    For i = 0 To ExtraCount - 1
        If ExtraKeys(i) = key Then Return ExtraValues(i)
    Next
    Return def
End Function

Sub Profile_SetValue(ByRef key As Const String, ByRef value As Const String)
    Dim As Integer i
    For i = 0 To ExtraCount - 1
        If ExtraKeys(i) = key Then ExtraValues(i) = value : Exit Sub
    Next
    If ExtraCount = 0 Then
        ReDim ExtraKeys(0 To 63)
        ReDim ExtraValues(0 To 63)
    ElseIf ExtraCount > UBound(ExtraKeys) Then
        ReDim Preserve ExtraKeys(0 To ExtraCount * 2)
        ReDim Preserve ExtraValues(0 To ExtraCount * 2)
    End If
    ExtraKeys(ExtraCount) = key
    ExtraValues(ExtraCount) = value
    ExtraCount += 1
End Sub

Private Sub ResetProfile(ByRef p As PlayerProfile)
    p.name = "Player" : p.avatar = 6 : p.created = "" : p.rating = 400 : p.ratedGames = 0
    p.gamesPlayed = 0 : p.wins = 0 : p.losses = 0 : p.draws = 0 : p.friendlyGames = 0
    p.checkmates = 0 : p.castledGames = 0 : p.promotions = 0 : p.winStreak = 0 : p.bestStreak = 0
    p.bestWinRating = 0 : p.tournamentsPlayed = 0 : p.tournamentsWon = 0 : p.careerStage = 0
    p.famousWatched = 0 : p.bestLevelBeaten = -1
    Erase ExtraKeys
    Erase ExtraValues
    ExtraCount = 0
End Sub

Private Function LoadProfile(ByRef id As Const String) As Boolean
    ResetProfile(Cur)
    Cur.id = id
    Dim As Integer f = FreeFile
    If Open(ProfilesDir & "/" & id & "/profile.ini" For Input As #f) <> 0 Then Return False
    Dim As String ln
    Do While Not EOF(f)
        Line Input #f, ln
        ln = Trim(ln, Any " " & Chr(9, 13))
        Dim As Integer eq = InStr(ln, "=")
        If ln = "" OrElse Left(ln, 1) = "#" OrElse eq = 0 Then Continue Do
        Dim As String k = Left(ln, eq - 1), v = Mid(ln, eq + 1)
        Select Case k
        Case "name" : Cur.name = v
        Case "avatar" : Cur.avatar = ValInt(v)
        Case "created" : Cur.created = v
        Case "rating" : Cur.rating = ValInt(v)
        Case "ratedGames" : Cur.ratedGames = ValInt(v)
        Case "gamesPlayed" : Cur.gamesPlayed = ValInt(v)
        Case "wins" : Cur.wins = ValInt(v)
        Case "losses" : Cur.losses = ValInt(v)
        Case "draws" : Cur.draws = ValInt(v)
        Case "friendlyGames" : Cur.friendlyGames = ValInt(v)
        Case "checkmates" : Cur.checkmates = ValInt(v)
        Case "castledGames" : Cur.castledGames = ValInt(v)
        Case "promotions" : Cur.promotions = ValInt(v)
        Case "winStreak" : Cur.winStreak = ValInt(v)
        Case "bestStreak" : Cur.bestStreak = ValInt(v)
        Case "bestWinRating" : Cur.bestWinRating = ValInt(v)
        Case "tournamentsPlayed" : Cur.tournamentsPlayed = ValInt(v)
        Case "tournamentsWon" : Cur.tournamentsWon = ValInt(v)
        Case "careerStage" : Cur.careerStage = ValInt(v)
        Case "famousWatched" : Cur.famousWatched = ValInt(v)
        Case "bestLevelBeaten" : Cur.bestLevelBeaten = ValInt(v)
        Case Else : Profile_SetValue(k, v)
        End Select
    Loop
    Close #f
    If Cur.avatar < 1 OrElse Cur.avatar > 6 Then Cur.avatar = 6
    If Cur.rating < 100 Then Cur.rating = 100
    If Cur.name = "" Then Cur.name = "Player"
    Return True
End Function

Sub Profile_Save()
    If Cur.id = "" Then Exit Sub
    Dim As String fn = ProfilesDir & "/" & Cur.id & "/profile.ini", tmp = fn & ".tmp"
    Dim As Integer f = FreeFile, i
    If Open(tmp For Output As #f) <> 0 Then Exit Sub
    Print #f, "# Beginner Chess player profile"
    Print #f, "name=" & Cur.name
    Print #f, "avatar=" & Cur.avatar
    Print #f, "created=" & Cur.created
    Print #f, "rating=" & Cur.rating
    Print #f, "ratedGames=" & Cur.ratedGames
    Print #f, "gamesPlayed=" & Cur.gamesPlayed
    Print #f, "wins=" & Cur.wins
    Print #f, "losses=" & Cur.losses
    Print #f, "draws=" & Cur.draws
    Print #f, "friendlyGames=" & Cur.friendlyGames
    Print #f, "checkmates=" & Cur.checkmates
    Print #f, "castledGames=" & Cur.castledGames
    Print #f, "promotions=" & Cur.promotions
    Print #f, "winStreak=" & Cur.winStreak
    Print #f, "bestStreak=" & Cur.bestStreak
    Print #f, "bestWinRating=" & Cur.bestWinRating
    Print #f, "tournamentsPlayed=" & Cur.tournamentsPlayed
    Print #f, "tournamentsWon=" & Cur.tournamentsWon
    Print #f, "careerStage=" & Cur.careerStage
    Print #f, "famousWatched=" & Cur.famousWatched
    Print #f, "bestLevelBeaten=" & Cur.bestLevelBeaten
    For i = 0 To ExtraCount - 1
        Print #f, ExtraKeys(i) & "=" & ExtraValues(i)
    Next
    Close #f
    If FileExists(fn) Then Kill fn
    Name tmp, fn
End Sub

Function Profile_Current() As PlayerProfile Ptr
    Return @Cur
End Function

Function Profile_Dir() As String
    Return ProfilesDir & "/" & Cur.id
End Function

Function Profile_Count() As Integer
    Return IdCount
End Function

Function Profile_IdAt(ByVal index As Integer) As String
    If index < 0 OrElse index >= IdCount Then Return ""
    Return IdList(index)
End Function

Function Profile_NameOf(ByRef id As Const String) As String
    Dim As Integer f = FreeFile
    Dim As String ln, result = id
    If Open(ProfilesDir & "/" & id & "/profile.ini" For Input As #f) <> 0 Then Return id
    Do While Not EOF(f)
        Line Input #f, ln
        If Left(ln, 5) = "name=" Then result = Trim(Mid(ln, 6), Any " " & Chr(13)) : Exit Do
    Loop
    Close #f
    Return result
End Function

Function Profile_Select(ByRef id As Const String) As Boolean
    If Cur.id <> "" Then Profile_Save()
    If Not LoadProfile(id) Then Return False
    '' Lessons and puzzles progress belongs to the profile.
    Progress_SetFile(Profile_Dir() & "/progress.ini")
    Progress_Load()
    Return True
End Function

Function Profile_Create(ByRef playerName As Const String) As String
    Dim As Integer n = 1
    Do While Dir(ProfilesDir & "/p" & n, fbDirectory) <> ""
        n += 1
    Loop
    Dim As String id = "p" & n
    MkDir ProfilesDir & "/" & id
    If Cur.id <> "" Then Profile_Save()
    ResetProfile(Cur)
    Cur.id = id
    Cur.name = IIf(Trim(playerName) = "", "Player", Left(Trim(playerName), 24))
    Dim As String d = Date()
    Cur.created = Mid(d, 7, 4) & "." & Left(d, 2) & "." & Mid(d, 4, 2)
    Profile_Save()
    Progress_SetFile(Profile_Dir() & "/progress.ini")
    Progress_Clear()
    Progress_Save()
    ScanProfiles()
    Return id
End Function

Function Profile_Rename(ByRef playerName As Const String) As Boolean
    If Trim(playerName) = "" Then Return False
    Cur.name = Left(Trim(playerName), 24)
    Profile_Save()
    Return True
End Function

Function Profile_Delete(ByRef id As Const String) As Boolean
    If IdCount <= 1 Then Return False                   '' keep at least one profile
    Dim As String folder = ProfilesDir & "/" & id
    Kill folder & "/profile.ini"
    Kill folder & "/progress.ini"
    Kill folder & "/history.txt"
    RmDir folder
    Dim As Boolean wasCurrent = (id = Cur.id)
    ScanProfiles()
    If wasCurrent Then
        Cur.id = ""
        Profile_Select(IdList(0))
    End If
    Return True
End Function

Sub Profile_Init(ByRef dataDir As Const String, ByRef preferredId As Const String)
    ProfilesDir = dataDir & "/profiles"
    If Dir(ProfilesDir, fbDirectory) = "" Then MkDir ProfilesDir
    Cur.id = ""
    ScanProfiles()
    If IdCount = 0 Then
        Profile_Create("Player")
        Exit Sub
    End If
    Dim As Integer i
    For i = 0 To IdCount - 1
        If IdList(i) = preferredId Then
            Profile_Select(preferredId)
            Exit Sub
        End If
    Next
    Profile_Select(IdList(0))
End Sub

'' ---------------------------------------------------------------------
'' Games and rating
'' ---------------------------------------------------------------------
Function Profile_RatingChange(ByVal rating As Integer, ByVal oppRating As Integer, _
                              ByVal score As Single, ByVal ratedGames As Integer) As Integer
    Dim As Double expected = 1 / (1 + 10 ^ ((oppRating - rating) / 400.0))
    '' Faster changes for new players, so the estimate settles quickly.
    Dim As Integer k = IIf(ratedGames < 20, 40, 24)
    Return CInt(k * (score - expected))
End Function

Function Profile_RankTitle(ByVal rating As Integer) As String
    Select Case rating
    Case Is < 600  : Return "Beginner"
    Case Is < 800  : Return "Apprentice"
    Case Is < 1000 : Return "Club Player"
    Case Is < 1200 : Return "Strong Player"
    Case Is < 1400 : Return "Expert"
    Case Is < 1600 : Return "Candidate Master"
    Case Is < 1800 : Return "Master"
    End Select
    Return "Grandmaster"
End Function

Function Profile_WinPercent() As Integer
    If Cur.gamesPlayed = 0 Then Return 0
    Return Int((Cur.wins + Cur.draws * 0.5) * 100 / Cur.gamesPlayed + 0.5)
End Function

Function Profile_RecordGame(ByRef rec As GameRecord) As Integer
    Dim As Integer change = 0
    If rec.kind = GK_TWO_PLAYER Then
        Cur.friendlyGames += 1
    Else
        Cur.gamesPlayed += 1
        If rec.score >= 1 Then
            Cur.wins += 1
            Cur.winStreak += 1
            If Cur.winStreak > Cur.bestStreak Then Cur.bestStreak = Cur.winStreak
            If rec.oppRating > Cur.bestWinRating Then Cur.bestWinRating = rec.oppRating
            If rec.level > Cur.bestLevelBeaten Then Cur.bestLevelBeaten = rec.level
            If rec.byMate Then Cur.checkmates += 1
        ElseIf rec.score > 0 Then
            Cur.draws += 1
            Cur.winStreak = 0
        Else
            Cur.losses += 1
            Cur.winStreak = 0
        End If
        If rec.rated Then
            change = Profile_RatingChange(Cur.rating, rec.oppRating, rec.score, Cur.ratedGames)
            Cur.rating += change
            If Cur.rating < 100 Then Cur.rating = 100
            Cur.ratedGames += 1
        End If
    End If
    If rec.castled Then Cur.castledGames += 1
    If rec.promoted Then Cur.promotions += 1
    Profile_Save()

    '' History line
    Dim As String kinds(0 To 3) = {"Game", "Two players", "Career", "Tournament"}
    Dim As String d = Date(), res = IIf(rec.score >= 1, "W", IIf(rec.score > 0, "D", "L"))
    Dim As Integer f = FreeFile
    If Open(Profile_Dir() & "/history.txt" For Append As #f) = 0 Then
        Print #f, Mid(d, 7, 4) & "." & Left(d, 2) & "." & Mid(d, 4, 2) & "|" & kinds(rec.kind) & "|" & _
                  rec.opponent & "|" & rec.oppRating & "|" & res & "|" & Cur.rating & "|" & change
        Close #f
    End If
    Return change
End Function

Function Profile_History(lines() As String, ByVal maxLines As Integer) As Integer
    Dim As String all()
    ReDim all(0 To 63)
    Dim As Integer n = 0, f = FreeFile
    If Open(Profile_Dir() & "/history.txt" For Input As #f) <> 0 Then Return 0
    Dim As String ln
    Do While Not EOF(f)
        Line Input #f, ln
        ln = Trim(ln, Any " " & Chr(13))
        If ln = "" Then Continue Do
        If n > UBound(all) Then ReDim Preserve all(0 To n * 2)
        all(n) = ln
        n += 1
    Loop
    Close #f
    Dim As Integer count = IIf(n < maxLines, n, maxLines), i
    ReDim lines(0 To IIf(count > 0, count - 1, 0))
    For i = 0 To count - 1
        lines(i) = all(n - 1 - i)
    Next
    Return count
End Function

'' ---------------------------------------------------------------------
'' Achievements
'' ---------------------------------------------------------------------
Const ACHIEVEMENT_TOTAL = 20
'' id | title | description  (one achievement per line)
Const ACH_TABLE = _
    "first-game|First Game|Finish your first game against the computer." & Chr(10) & _
    "first-victory|First Victory|Win a game against the computer." & Chr(10) & _
    "first-checkmate|First Checkmate|Checkmate the computer." & Chr(10) & _
    "ten-games|Ten Games Played|Play ten games against the computer." & Chr(10) & _
    "fifty-games|Fifty Games Played|Play fifty games against the computer." & Chr(10) & _
    "hat-trick|Hat Trick|Win three games in a row." & Chr(10) & _
    "castling-expert|Castling Expert|Castle in ten different games." & Chr(10) & _
    "new-queen|New Queen|Promote a pawn in a game." & Chr(10) & _
    "strong-opponent|Strong Opponent|Beat the computer at Normal level or stronger." & Chr(10) & _
    "giant-slayer|Giant Slayer|Beat the computer at Advanced level." & Chr(10) & _
    "puzzle-solver|Puzzle Solver|Solve your first puzzle." & Chr(10) & _
    "ten-puzzles|Ten Puzzles Solved|Solve ten puzzles." & Chr(10) & _
    "puzzle-master|Puzzle Master|Solve every puzzle." & Chr(10) & _
    "fork-expert|Fork Expert|Solve all the fork puzzles." & Chr(10) & _
    "eager-student|Eager Student|Complete your first lesson." & Chr(10) & _
    "first-steps|First Steps Graduate|Complete the whole 'First steps' chapter." & Chr(10) & _
    "chess-scholar|Chess Scholar|Complete every lesson." & Chr(10) & _
    "champion|Champion|Win a tournament." & Chr(10) & _
    "career-master|Master Slayer|Beat every opponent in the Career ladder." & Chr(10) & _
    "history-fan|History Fan|Watch a famous game all the way to the end."

Dim Shared AchIds(0 To ACHIEVEMENT_TOTAL - 1) As String
Dim Shared AchTitles(0 To ACHIEVEMENT_TOTAL - 1) As String
Dim Shared AchDescs(0 To ACHIEVEMENT_TOTAL - 1) As String
Dim Shared AchReady As Boolean = False

Private Sub InitAchievements()
    If AchReady Then Exit Sub
    Dim As String rest = ACH_TABLE & Chr(10)
    Dim As Integer i = 0
    Do While Len(rest) > 0 AndAlso i < ACHIEVEMENT_TOTAL
        Dim As Integer nl = InStr(rest, Chr(10))
        Dim As String ln = Left(rest, nl - 1)
        rest = Mid(rest, nl + 1)
        Dim As Integer b1 = InStr(ln, "|"), b2 = InStr(b1 + 1, ln, "|")
        AchIds(i) = Left(ln, b1 - 1)
        AchTitles(i) = Mid(ln, b1 + 1, b2 - b1 - 1)
        AchDescs(i) = Mid(ln, b2 + 1)
        i += 1
    Loop
    AchReady = True
End Sub

Function Ach_Count() As Integer
    Return ACHIEVEMENT_TOTAL
End Function

Function Ach_Id(ByVal i As Integer) As String
    InitAchievements()
    Return AchIds(i)
End Function

Function Ach_Title(ByVal i As Integer) As String
    InitAchievements()
    Return AchTitles(i)
End Function

Function Ach_Description(ByVal i As Integer) As String
    InitAchievements()
    Return AchDescs(i)
End Function

Function Ach_Unlocked(ByVal i As Integer) As Boolean
    InitAchievements()
    Return Profile_GetValue("ach." & AchIds(i)) <> ""
End Function

Function Ach_UnlockedCount() As Integer
    Dim As Integer i, n = 0
    For i = 0 To ACHIEVEMENT_TOTAL - 1
        If Ach_Unlocked(i) Then n += 1
    Next
    Return n
End Function

Function Ach_CheckAll(ByVal lessonTotal As Integer, ByVal puzzleTotal As Integer, _
                      ByVal chapter1Done As Boolean, ByVal forkDone As Boolean, _
                      ByVal careerTotal As Integer) As String
    InitAchievements()
    Dim As Integer solved = Progress_PuzzlesSolved(), lessons = Progress_LessonsDone()
    Dim As Boolean earned(0 To ACHIEVEMENT_TOTAL - 1)
    earned(0) = Cur.gamesPlayed >= 1
    earned(1) = Cur.wins >= 1
    earned(2) = Cur.checkmates >= 1
    earned(3) = Cur.gamesPlayed >= 10
    earned(4) = Cur.gamesPlayed >= 50
    earned(5) = Cur.bestStreak >= 3
    earned(6) = Cur.castledGames >= 10
    earned(7) = Cur.promotions >= 1
    earned(8) = Cur.bestLevelBeaten >= 2
    earned(9) = Cur.bestLevelBeaten >= 4
    earned(10) = solved >= 1
    earned(11) = solved >= 10
    earned(12) = puzzleTotal > 0 AndAlso solved >= puzzleTotal
    earned(13) = forkDone
    earned(14) = lessons >= 1
    earned(15) = chapter1Done
    earned(16) = lessonTotal > 0 AndAlso lessons >= lessonTotal
    earned(17) = Cur.tournamentsWon >= 1
    earned(18) = careerTotal > 0 AndAlso Cur.careerStage >= careerTotal
    earned(19) = Cur.famousWatched >= 1
    Dim As String newly = ""
    Dim As Integer i
    Dim As String d = Date()
    For i = 0 To ACHIEVEMENT_TOTAL - 1
        If earned(i) AndAlso Not Ach_Unlocked(i) Then
            Profile_SetValue("ach." & AchIds(i), Mid(d, 7, 4) & "." & Left(d, 2) & "." & Mid(d, 4, 2))
            newly &= IIf(newly = "", "", "|") & AchTitles(i)
        End If
    Next
    If newly <> "" Then Profile_Save()
    Return newly
End Function
