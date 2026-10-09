'' =====================================================================
'' BeginnerChess - profileui.bas
'' Player Profile screen (statistics, rating, achievements, recent games,
'' switching players) and the achievement check used by other screens.
'' =====================================================================
#include once "screens.bi"
#include once "lessons.bi"
#include once "puzzles.bi"
#include once "progress.bi"

Function LevelRating(ByVal level As Integer) As Integer
    Dim As Integer r(0 To 4) = {500, 800, 1100, 1400, 1700}
    If level < 0 OrElse level > 4 Then Return 1100
    Return r(level)
End Function

Sub App_CheckAchievements()
    '' Course facts the achievements depend on
    Dim As Integer i
    Dim As Boolean chapter1Done = (Lessons_Count() > 0)
    Dim As String firstChapter = Lessons_ChapterName(0)
    For i = 0 To Lessons_Count() - 1
        If Lessons_Get(i)->chapter = firstChapter AndAlso Not Progress_IsLessonDone(Lessons_Get(i)->id) Then chapter1Done = False
    Next
    Dim As Boolean forkDone = False, anyFork = False
    forkDone = True
    For i = 0 To Puzzles_Count() - 1
        If LCase(Puzzles_Get(i)->category) = "fork" Then
            anyFork = True
            If Not Progress_IsPuzzleSolved(Puzzles_Get(i)->id) Then forkDone = False
        End If
    Next
    If Not anyFork Then forkDone = False
    Dim As String newly = Ach_CheckAll(Lessons_Count(), Puzzles_Count(), chapter1Done, forkDone, Career_Count())
    If newly = "" OrElse Not AppConfig.achievementsOn Then Exit Sub
    Audio_Play(SND_SOLVED)
    Dim As String rest = newly & "|"
    Do While Len(rest) > 1
        Dim As Integer p = InStr(rest, "|")
        UI_ShowToast("Achievement unlocked!", Left(rest, p - 1))
        rest = Mid(rest, p + 1)
    Loop
End Sub

'' ---------------------------------------------------------------------
Dim Shared PFPieces As PieceImages
Dim Shared PFInput As InputDialogState
Dim Shared PFDlg As DialogState
Dim Shared PFSwitching As Boolean = False
Dim Shared PFDeleteId As String

Private Sub DrawStatRow(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, _
                        ByRef label As Const String, ByRef value As Const String)
    Text_Draw(x, y, label, 18, RGB(110, 95, 80))
    Text_Draw(x + w - Text_Width(value, 18), y, value, 18, RGB(40, 34, 28))
End Sub

Private Sub SwitchTo(ByRef id As Const String)
    Profile_Select(id)
    AppConfig.activeProfile = id
    Settings_Save(AppConfig, Settings_FileName())
End Sub

Function Profile_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_PROFILE
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    UI.blockInput = PFInput.active OrElse PFDlg.active
    UI_DrawBackground()
    Screen_DrawHeader("Player Profile")
    Dim As PlayerProfile Ptr pr = Profile_Current()
    If PFPieces.size <> 96 OrElse PFPieces.style <> AppConfig.pieceSet Then Pieces_Build(PFPieces, 96, AppConfig.pieceSet)

    '' ---- Left: who you are and your numbers ----
    Dim As Integer lx = 24, lw = 440, ly = 62, lh = sh - ly - 84
    Gfx_Panel(lx, ly, lw, lh, 16, RGB(250, 246, 236), RGB(120, 90, 56))
    Gfx_FillCircle(lx + 70, ly + 70, 54, RGB(230, 214, 180))
    Pieces_Draw(PFPieces, MAKE_PIECE(SIDE_WHITE, pr->avatar), lx + 22, ly + 22)
    Dim As Integer ns = 30
    Do While ns > 16 AndAlso Text_Width(pr->name, ns) > lw - 160
        ns -= 1
    Loop
    Text_Draw(lx + 140, ly + 24, pr->name, ns, RGB(80, 52, 24))
    Text_Draw(lx + 140, ly + 64, Profile_RankTitle(pr->rating), 20, RGB(52, 100, 170))
    Text_Draw(lx + 140, ly + 90, "Rating " & pr->rating, 24, RGB(40, 34, 28))
    If UI_Hover(lx + 140, ly + 88, 200, 30) Then
        UI_SetTooltip("pf.rating", "Your rating is a Beginner Chess estimate based on your games against the " & _
                      "computer opponents (without take-backs). It is not an official FIDE rating.")
    End If

    Dim As Integer bw = (lw - 50) \ 3, by = ly + 140
    If UI_Button("pf.name", lx + 20, by, bw, 38, "Change name", True, "Type a new name.") Then
        InputDialog_Open(PFInput, "name", "Your name", "What is your name?", pr->name, "OK|Cancel", 24)
    End If
    If UI_Button("pf.pic", lx + 25 + bw, by, bw, 38, "Picture", True, "Choose a different chess piece as your picture.") Then
        pr->avatar = (pr->avatar Mod 6) + 1
        Profile_Save()
    End If
    If UI_Button("pf.switch", lx + 30 + 2 * bw, by, bw, 38, "Players...", True, "Switch to another player or add a new one.", BTN_PRIMARY) Then
        PFSwitching = Not PFSwitching
    End If

    '' Statistics
    Dim As Integer sx = lx + 24, sw2 = lw - 48, sy = by + 56, rowH = 27
    Dim As Integer lessonsDone = Progress_LessonsDone(), solved = Progress_PuzzlesSolved()
    DrawStatRow(sx, sy, sw2, "Games against the computer", Str(pr->gamesPlayed)) : sy += rowH
    DrawStatRow(sx, sy, sw2, "Wins / Draws / Losses", pr->wins & " / " & pr->draws & " / " & pr->losses) : sy += rowH
    DrawStatRow(sx, sy, sw2, "Score", Profile_WinPercent() & " %") : sy += rowH
    DrawStatRow(sx, sy, sw2, "Checkmates given", Str(pr->checkmates)) : sy += rowH
    DrawStatRow(sx, sy, sw2, "Best winning streak", Str(pr->bestStreak)) : sy += rowH
    DrawStatRow(sx, sy, sw2, "Two-player games", Str(pr->friendlyGames)) : sy += rowH
    DrawStatRow(sx, sy, sw2, "Puzzles solved / tried", solved & " / " & Progress_PuzzlesAttempted() & _
                "   (of " & Puzzles_Count() & ")") : sy += rowH
    DrawStatRow(sx, sy, sw2, "Lessons completed", lessonsDone & " of " & Lessons_Count()) : sy += rowH
    DrawStatRow(sx, sy, sw2, "Tournaments won / played", pr->tournamentsWon & " / " & pr->tournamentsPlayed) : sy += rowH
    DrawStatRow(sx, sy, sw2, "Career", IIf(pr->careerStage >= Career_Count(), "completed!", _
                pr->careerStage & " of " & Career_Count() & " opponents beaten")) : sy += rowH
    If pr->bestWinRating > 0 Then DrawStatRow(sx, sy, sw2, "Strongest opponent beaten", Str(pr->bestWinRating)) : sy += rowH
    If pr->created <> "" Then Text_Draw(sx, ly + lh - 28, "Player since " & pr->created, 15, RGB(140, 125, 110))

    '' ---- Right: achievements and recent games ----
    Dim As Integer rx = lx + lw + 20, rw = sw - rx - 24, ry = 62
    Dim As Integer achH = IIf(AppConfig.achievementsOn, 330, 70)
    Gfx_Panel(rx, ry, rw, achH, 16, RGB(250, 246, 236), RGB(120, 90, 56))
    If AppConfig.achievementsOn Then
        Text_Draw(rx + 18, ry + 12, "Achievements  " & Ach_UnlockedCount() & " / " & Ach_Count(), 22, RGB(80, 52, 24))
        Dim As Integer cols = 5, cw = (rw - 36) \ cols, chh = 70, i
        For i = 0 To Ach_Count() - 1
            Dim As Integer cx = rx + 18 + (i Mod cols) * cw, cy = ry + 46 + (i \ cols) * chh
            Dim As Boolean got = Ach_Unlocked(i)
            Gfx_FillCircle(cx + cw \ 2, cy + 18, 17, IIf(got, RGB(230, 170, 30), RGB(205, 205, 210)))
            Gfx_FillCircle(cx + cw \ 2, cy + 18, 12, IIf(got, RGB(255, 215, 80), RGB(225, 225, 230)))
            Text_DrawCentered(cx + cw \ 2, cy + 9, IIf(got, "*", "?"), 18, IIf(got, RGB(150, 90, 10), RGB(160, 160, 165)))
            Text_DrawWrapped(cx + 2, cy + 38, cw - 4, Ach_Title(i), 13, IIf(got, RGB(70, 46, 22), RGB(150, 150, 155)), True)
            If UI_Hover(cx, cy, cw, chh) Then
                UI_SetTooltip("pf.ach" & i, Ach_Title(i) & ": " & Ach_Description(i) & IIf(got, " (unlocked)", ""))
            End If
        Next
    Else
        Text_DrawWrapped(rx + 18, ry + 14, rw - 36, "Achievements are switched off. You can switch them on in Options.", _
                         18, RGB(110, 95, 80))
    End If

    Dim As Integer hy = ry + achH + 14, hh = sh - hy - 84
    Gfx_Panel(rx, hy, rw, hh, 16, RGB(255, 255, 255), RGB(120, 90, 56))
    Text_Draw(rx + 18, hy + 10, "Recent games", 20, RGB(80, 52, 24))
    Dim As String lines()
    Dim As Integer n = Profile_History(lines(), (hh - 46) \ 24), k
    If n = 0 Then Text_Draw(rx + 18, hy + 44, "No games yet. Go and play!", 18, RGB(140, 140, 150))
    For k = 0 To n - 1
        '' date|kind|opponent|rating|W/D/L|ratingAfter|change
        Dim As String f(0 To 6), rest = lines(k) & "|"
        Dim As Integer j
        For j = 0 To 6
            Dim As Integer p = InStr(rest, "|")
            If p = 0 Then Exit For
            f(j) = Left(rest, p - 1) : rest = Mid(rest, p + 1)
        Next
        Dim As Integer yy = hy + 40 + k * 24
        Dim As ULong rc = IIf(f(4) = "W", RGB(30, 130, 50), IIf(f(4) = "D", RGB(60, 90, 160), RGB(180, 60, 40)))
        Dim As String resWord = IIf(f(4) = "W", "won", IIf(f(4) = "D", "draw", "lost"))
        Text_Draw(rx + 18, yy, f(0), 15, RGB(140, 125, 110))
        Text_Draw(rx + 120, yy, Left(f(1) & ": " & f(2), (rw - 260) \ 8), 16, RGB(40, 34, 28))
        Text_Draw(rx + rw - 130, yy, resWord, 16, rc)
        If ValInt(f(6)) <> 0 Then Text_Draw(rx + rw - 70, yy, IIf(ValInt(f(6)) > 0, "+", "") & f(6), 16, rc)
    Next

    '' ---- Player switcher ----
    If PFSwitching Then
        Dim As Integer ox = lx + 40, oy = by + 46, ow = lw - 80, oh = 60 + (Profile_Count() + 1) * 46
        Gfx_Panel(ox, oy, ow, oh, 12, RGB(255, 252, 240), RGB(52, 120, 206))
        Text_Draw(ox + 14, oy + 10, "Who is playing?", 20, RGB(40, 60, 110))
        Dim As Integer i
        For i = 0 To Profile_Count() - 1
            Dim As String id = Profile_IdAt(i)
            Dim As Integer yy = oy + 44 + i * 46
            If UI_Button("pf.sel" & id, ox + 12, yy, ow - 120, 38, Profile_NameOf(id), True, "Play as this player.", _
                         IIf(id = pr->id, BTN_PRIMARY, BTN_MENU)) Then
                SwitchTo(id)
                PFSwitching = False
            End If
            If UI_Button("pf.del" & id, ox + ow - 100, yy, 88, 38, "Delete", Profile_Count() > 1, _
                         "Delete this player and all of their statistics.") Then
                PFDeleteId = id
                Dialog_Open(PFDlg, "del", "Delete player?", "Delete '" & Profile_NameOf(id) & _
                            "' with all statistics, achievements and progress? This cannot be undone.", "Delete|Cancel")
            End If
        Next
        If UI_Button("pf.new", ox + 12, oy + 44 + Profile_Count() * 46, ow - 24, 38, "+ New player", True, _
                     "Add a new player with fresh statistics.") Then
            InputDialog_Open(PFInput, "new", "New player", "What is the new player's name?", "", "Create|Cancel", 24)
        End If
    End If

    Dim As Boolean goBack = UI_Button("pf.back", 20, sh - 64, 140, 46, "< Back", True, "Return to the main menu.")
    If CBool(UI.keyCode = KEY_ESCAPE) AndAlso Not PFInput.active AndAlso Not PFDlg.active Then
        If PFSwitching Then PFSwitching = False Else goBack = True
    End If
    If goBack Then nextScreen = SCREEN_MENU

    '' Dialogs
    If PFInput.active Then
        Select Case InputDialog_Run(PFInput)
        Case 0
            If Trim(PFInput.text) = "" Then
                PFInput.errorText = "Please type a name."
            Else
                If PFInput.id = "name" Then
                    Profile_Rename(PFInput.text)
                Else
                    Dim As String id = Profile_Create(PFInput.text)
                    SwitchTo(id)
                    PFSwitching = False
                End If
                PFInput.active = False
            End If
        Case 1
            PFInput.active = False
        End Select
    ElseIf PFDlg.active Then
        Dim As Integer r = Dialog_Run(PFDlg)
        If r = 0 Then
            Profile_Delete(PFDeleteId)
            AppConfig.activeProfile = Profile_Current()->id
            Settings_Save(AppConfig, Settings_FileName())
        End If
    End If
    Return nextScreen
End Function
