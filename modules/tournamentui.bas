'' =====================================================================
'' BeginnerChess - tournamentui.bas
'' The Tournament hall: the Career ladder and the three tournaments.
'' =====================================================================
#include once "screens.bi"

Dim Shared THPieces As PieceImages
Dim Shared THDlg As DialogState
Dim Shared THPendingTier As Integer = -1

Private Sub DrawAvatar(ByVal pt As Integer, ByVal cx As Integer, ByVal cy As Integer, ByVal dark As Boolean)
    Gfx_FillCircle(cx, cy, 21, IIf(dark, RGB(200, 200, 205), RGB(230, 214, 180)))
    Pieces_Draw(THPieces, MAKE_PIECE(IIf(dark, SIDE_BLACK, SIDE_WHITE), pt), cx - 18, cy - 18)
End Sub

Function Tournament_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_TOURNAMENT
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    UI.blockInput = THDlg.active
    UI_DrawBackground()
    Screen_DrawHeader("Tournament")
    If THPieces.size <> 36 OrElse THPieces.style <> AppConfig.pieceSet Then Pieces_Build(THPieces, 36, AppConfig.pieceSet)
    Dim As PlayerProfile Ptr pr = Profile_Current()
    Text_Draw(24, 60, pr->name & "  -  rating " & pr->rating & " (" & Profile_RankTitle(pr->rating) & ")", 22, _
              RGB(240, 230, 210))
    Text_Draw(sw - 330, 64, "Ratings are Beginner Chess estimates.", 15, RGB(160, 176, 200))

    '' ---- Career ladder ----
    Dim As Integer lx = 24, lw = (sw - 72) \ 2, ly = 94, lh = sh - ly - 84
    Gfx_Panel(lx, ly, lw, lh, 16, RGB(250, 246, 236), RGB(120, 90, 56))
    Text_Draw(lx + 18, ly + 12, "Career", 26, RGB(80, 52, 24))
    Text_Draw(lx + 120, ly + 18, "Beat each opponent to meet the next one.", 15, RGB(120, 100, 80))
    Dim As Integer i, rowH = (lh - 56) \ Career_Count()
    For i = 0 To Career_Count() - 1
        Dim As Opponent Ptr o = Career_Opponent(i)
        Dim As Integer y = ly + 50 + i * rowH
        Dim As Boolean beaten = (i < pr->careerStage), current = (i = pr->careerStage), locked = (i > pr->careerStage)
        If current Then Gfx_RoundRect(lx + 8, y - 2, lw - 16, rowH - 4, 10, RGB(255, 236, 170))
        DrawAvatar(o->avatar, lx + 36, y + rowH \ 2 - 2, locked)
        Text_Draw(lx + 66, y + 4, o->name & "  " & o->rating, 20, IIf(locked, RGB(150, 150, 155), RGB(60, 40, 20)))
        Text_Draw(lx + 66, y + 28, Engine_StyleName(o->style) & ", " & Engine_LevelName(o->level), 14, RGB(130, 115, 100))
        If UI_Hover(lx + 8, y, lw - 140, rowH - 4) Then UI_SetTooltip("th.c" & i, o->bio)
        Dim As Integer bx = lx + lw - 118
        If beaten Then
            Gfx_DoneBadge(bx - 20, y + rowH \ 2 - 2, 12)
            If UI_Button("th.re" & i, bx, y + 6, 100, rowH - 16, "Rematch", True, "Play " & o->name & " again (the career does not change).") Then
                Play_StartRated(GK_CAREER, *o, IIf(Rnd < 0.5, SIDE_WHITE, SIDE_BLACK), i)
                nextScreen = SCREEN_PLAY
            End If
        ElseIf current Then
            If UI_Button("th.play" & i, bx, y + 6, 100, rowH - 16, "Play", True, "Challenge " & o->name & "!", BTN_PRIMARY) Then
                Play_StartRated(GK_CAREER, *o, IIf(Rnd < 0.5, SIDE_WHITE, SIDE_BLACK), i)
                nextScreen = SCREEN_PLAY
            End If
        Else
            Text_Draw(bx + 20, y + rowH \ 2 - 10, "locked", 16, RGB(160, 160, 165))
        End If
    Next
    If pr->careerStage >= Career_Count() Then
        Text_DrawCentered(lx + lw \ 2, ly + lh - 26, "You have beaten everyone. You are a true champion!", 16, RGB(30, 120, 50))
    End If

    '' ---- Tournaments ----
    Dim As Integer rx = lx + lw + 24, rw = sw - rx - 24, ry = ly, rh = lh
    Gfx_Panel(rx, ry, rw, rh, 16, RGB(250, 246, 236), RGB(120, 90, 56))
    Text_Draw(rx + 18, ry + 12, "Tournaments", 26, RGB(80, 52, 24))
    Dim As Integer active = IIf(Tour_Active(), Tour_ActiveTier(), -1)
    Dim As Integer ty = ry + 52, t
    For t = 0 To Tour_TierCount() - 1
        If t = active Then Continue For            '' the active one is shown in detail below
        Dim As Boolean tierOpen = Tour_TierUnlocked(t)
        Dim As Integer lo = Tour_Opponent(t, 0)->rating, hi = Tour_Opponent(t, 3)->rating
        Text_Draw(rx + 18, ty + 4, Tour_TierName(t), 20, IIf(tierOpen, RGB(60, 40, 20), RGB(150, 150, 155)))
        Text_Draw(rx + 18, ty + 28, "Opponents " & lo & " - " & hi & IIf(Profile_GetValue("tourwon." & t) <> "", "   (you won it!)", ""), _
                  14, RGB(130, 115, 100))
        If UI_Button("th.t" & t, rx + rw - 118, ty + 6, 100, 38, "Start", tierOpen AndAlso CBool(active < 0), _
                     IIf(Not tierOpen, Tour_TierLockText(t), IIf(active >= 0, "Finish your current tournament first.", _
                         "Four games, one against each opponent.")), BTN_PRIMARY) Then
            Tour_Start(t)
        End If
        ty += 56
    Next

    If active >= 0 Then
        '' Standings of the running tournament
        Dim As Integer sy = ty + 6
        Gfx_RoundRect(rx + 10, sy - 6, rw - 20, ry + rh - sy - 4, 10, RGB(255, 252, 240))
        Text_Draw(rx + 20, sy, Tour_TierName(active), 22, RGB(52, 100, 170))
        Dim As Boolean done = Tour_Finished()
        Text_Draw(rx + 20, sy + 28, IIf(done, "Final standings", "Round " & Tour_Round() & " of 4"), 16, RGB(120, 100, 80))
        '' Sort participants by score
        Dim As Integer order(0 To 4) = {0, 1, 2, 3, 4}, a, b
        For a = 0 To 3
            For b = a + 1 To 4
                If Tour_Score(order(b)) > Tour_Score(order(a)) OrElse _
                   (Tour_Score(order(b)) = Tour_Score(order(a)) AndAlso order(b) = TOUR_PLAYER) Then Swap order(a), order(b)
            Next
        Next
        For a = 0 To 4
            Dim As Integer who = order(a), yy = sy + 52 + a * 26
            Dim As String nm = IIf(who = TOUR_PLAYER, pr->name & " (you)", Tour_Opponent(active, who)->name)
            Dim As String rt = IIf(who = TOUR_PLAYER, Str(pr->rating), Str(Tour_Opponent(active, who)->rating))
            Dim As Integer sc = Tour_Score(who)
            Dim As ULong c = IIf(who = TOUR_PLAYER, RGB(30, 110, 50), RGB(50, 44, 36))
            Text_Draw(rx + 24, yy, (a + 1) & ". " & nm, 17, c)
            Text_Draw(rx + rw - 150, yy, rt, 15, RGB(140, 125, 110))
            Text_Draw(rx + rw - 80, yy, (sc \ 2) & IIf(sc Mod 2 = 1, ".5", ""), 17, c)
        Next
        Dim As Integer by = sy + 52 + 5 * 26 + 12
        If done Then
            Dim As Integer place = Tour_PlayerPlace()
            Text_DrawWrapped(rx + 20, by, rw - 40, IIf(place = 1, "You won the tournament! Congratulations, champion!", _
                             "You finished in place " & place & ". Well played - try again to win it!"), 18, _
                             IIf(place = 1, RGB(30, 130, 50), RGB(60, 60, 110)))
            If UI_Button("th.close", rx + 20, by + 50, rw - 40, 42, "Close tournament", True, "Save the result and choose a new tournament.", BTN_PRIMARY) Then
                Tour_Complete()
                App_CheckAchievements()
                If place = 1 Then Audio_Play(SND_VICTORY)
            End If
        Else
            Dim As Integer oi = Tour_NextOpponent()
            Dim As Opponent Ptr o = Tour_Opponent(active, oi)
            Dim As Boolean white = Tour_PlayerIsWhite()
            If UI_Button("th.next", rx + 20, by, rw - 150, 42, "Play " & o->name & " (" & IIf(white, "White", "Black") & ")", True, _
                         o->bio, BTN_PRIMARY) Then
                Play_StartRated(GK_TOURNAMENT, *o, IIf(white, SIDE_WHITE, SIDE_BLACK), -1)
                nextScreen = SCREEN_PLAY
            End If
            If UI_Button("th.quit", rx + rw - 120, by, 100, 42, "Give up", True, "Leave this tournament (it will not count).") Then
                THPendingTier = active
                Dialog_Open(THDlg, "quit", "Give up the tournament?", "Leave the " & Tour_TierName(active) & _
                            "? The games played so far will be forgotten.", "Give up|Stay")
            End If
        End If
    End If

    Dim As Boolean goBack = UI_Button("th.back", 20, sh - 64, 140, 46, "< Back", True, "Return to the main menu.")
    If UI.keyCode = KEY_ESCAPE AndAlso Not THDlg.active Then goBack = True
    If goBack Then nextScreen = SCREEN_MENU
    If THDlg.active Then
        If Dialog_Run(THDlg) = 0 Then Tour_Abandon()
    End If
    Return nextScreen
End Function
