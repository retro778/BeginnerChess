'' =====================================================================
'' BeginnerChess - learn.bas
'' "Learn Chess" (lesson list + lesson player) and "Chess Puzzles"
'' (puzzle list + puzzle player) screens.
'' =====================================================================
#include once "screens.bi"
#include once "boardctl.bi"
#include once "lessons.bi"
#include once "puzzles.bi"
#include once "progress.bi"

Dim Shared LearnBoard As BoardView
Dim Shared LearnBC As BoardControl
Dim Shared LearnDlg As DialogState

'' Positions the board on the left and returns the x of the side panel.
Private Function LayoutBoard(ByVal flipped As Boolean) As Integer
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    LearnBoard.theme = AppConfig.boardTheme
    LearnBoard.pieceSet = AppConfig.pieceSet
    LearnBoard.showCoords = AppConfig.showCoordinates
    LearnBoard.flipped = flipped
    Board_Layout(LearnBoard, 0, 0, 10)
    Dim As Integer panelMin = 400
    Dim As Integer sq = (sh - 50 - 24 - 2 * LearnBoard.margin) \ 8
    If sq * 8 + 2 * LearnBoard.margin > sw - panelMin - 48 Then sq = (sw - panelMin - 48 - 2 * LearnBoard.margin) \ 8
    Board_Layout(LearnBoard, 0, 0, sq)
    Dim As Integer outer = Board_OuterSize(LearnBoard)
    Board_Layout(LearnBoard, 16, 50 + (sh - 50 - outer) \ 2, sq)
    Return 16 + outer + 20
End Function

Private Function Stars(ByVal n As Integer) As String
    Dim As String s = ""
    Dim As Integer i
    For i = 1 To 5
        s &= IIf(i <= n, "*", ".")
    Next
    Return s
End Function

'' =====================================================================
'' Lesson list
'' =====================================================================
Dim Shared LLChapter As Integer = 0
Dim Shared LLScroll As Integer = 0

Private Function ChapterDone(ByVal c As Integer, ByRef total As Integer) As Integer
    Dim As Integer i, done = 0
    total = 0
    For i = 0 To Lessons_Count() - 1
        Dim As Lesson Ptr L = Lessons_Get(i)
        If L->chapter = Lessons_ChapterName(c) Then
            total += 1
            If Progress_IsLessonDone(L->id) Then done += 1
        End If
    Next
    Return done
End Function

Declare Sub LessonPlay_Start(ByVal index As Integer)

'' Completed lessons / solved puzzles among those that are installed.
Private Function LessonsDoneHere() As Integer
    Dim As Integer i, n = 0
    For i = 0 To Lessons_Count() - 1
        If Progress_IsLessonDone(Lessons_Get(i)->id) Then n += 1
    Next
    Return n
End Function

Private Function PuzzlesSolvedHere() As Integer
    Dim As Integer i, n = 0
    For i = 0 To Puzzles_Count() - 1
        If Progress_IsPuzzleSolved(Puzzles_Get(i)->id) Then n += 1
    Next
    Return n
End Function

Function LessonList_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_LESSONS
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    UI_DrawBackground()
    Screen_DrawHeader("Learn Chess")
    If Lessons_Count() = 0 Then
        Text_DrawWrapped(40, 120, sw - 80, "No lessons were found. The lesson files belong in " & ExePath() & _
                         "/data/lessons.", 24, RGB(240, 220, 200))
    Else
        Text_Draw(24, 62, "Lessons completed: " & LessonsDoneHere() & " of " & Lessons_Count(), 22, RGB(240, 230, 210))
    End If

    '' Chapters on the left
    Dim As Integer cx = 24, cw = 300, cy = 100, c
    For c = 0 To Lessons_ChapterCount() - 1
        Dim As Integer total, done = ChapterDone(c, total)
        Dim As String label = Lessons_ChapterName(c) & "  " & done & "/" & total
        If UI_Button("ll.ch" & c, cx, cy + c * 56, cw, 48, label, True, "", _
                     IIf(c = LLChapter, BTN_PRIMARY, BTN_MENU)) Then
            LLChapter = c
            LLScroll = 0
        End If
    Next

    '' Lessons of the chapter on the right
    Dim As Integer lx = cx + cw + 24, lw = sw - lx - 24, ly = 100, rowH = 62
    Dim As Integer visible = (sh - 90 - ly) \ rowH
    Dim As Integer ids(0 To 63), n = 0, i
    For i = 0 To Lessons_Count() - 1
        If Lessons_Get(i)->chapter = Lessons_ChapterName(LLChapter) AndAlso n < 64 Then ids(n) = i : n += 1
    Next
    If UI_Hover(lx, ly, lw, visible * rowH) AndAlso UI.wheelDelta <> 0 Then LLScroll -= UI.wheelDelta
    If LLScroll > n - visible Then LLScroll = n - visible
    If LLScroll < 0 Then LLScroll = 0
    For i = LLScroll To LLScroll + visible - 1
        If i >= n Then Exit For
        Dim As Lesson Ptr L = Lessons_Get(ids(i))
        Dim As Integer y = ly + (i - LLScroll) * rowH
        Dim As Boolean done = Progress_IsLessonDone(L->id)
        If UI_Button("ll.l" & ids(i), lx, y, lw, rowH - 8, "", True, L->summary, BTN_MENU) Then
            LessonPlay_Start(ids(i))
            nextScreen = SCREEN_LESSON
        End If
        Text_Draw(lx + 16, y + 8, (i + 1) & ". " & L->title, 22, RGB(70, 46, 22))
        Text_Draw(lx + 40, y + 34, L->summary, 16, RGB(120, 100, 80))
        If done Then
            Gfx_DoneBadge(lx + lw - 30, y + (rowH - 8) \ 2, 14)
        End If
    Next
    If n > visible Then Text_Draw(lx, sh - 50, "Scroll with the mouse wheel for more lessons.", 16, RGB(160, 176, 200))

    Dim As Boolean goBack = UI_Button("ll.back", 20, sh - 64, 140, 46, "< Back", True, "Return to the main menu.")
    If UI.keyCode = KEY_ESCAPE Then goBack = True
    If goBack Then nextScreen = SCREEN_MENU
    Return nextScreen
End Function

'' =====================================================================
'' Lesson player
'' =====================================================================
Type LessonPlayState
    index        As Integer
    stepIdx      As Integer
    pos          As Position
    legalPos     As Boolean
    goalIdx      As Integer
    taskDone     As Boolean
    feedback     As String
    feedbackKind As Integer       '' 0 info, 1 error, 2 good
    replyPending As Boolean
    replyAt      As Double
    replyMove    As ChessMove
    engineReply  As Boolean       '' play goals: computer to move
    thinkStart   As Double
    playerMoves  As Integer
    hintShown    As Boolean
    finished     As Boolean
    flipped      As Boolean       '' board orientation, fixed for the whole step
End Type
Dim Shared LP As LessonPlayState

Private Function CurLesson() As Lesson Ptr
    Return Lessons_Get(LP.index)
End Function

Private Function CurStep() As LessonStep Ptr
    Return @(CurLesson()->steps(LP.stepIdx))
End Function

Private Sub StartStep(ByVal stepIdx As Integer)
    Engine_StopAsync()
    LP.stepIdx = stepIdx
    Dim As String why
    Lesson_StepPosition(*CurStep(), LP.pos, LP.legalPos, why)
    BC_Reset(LearnBC)
    LP.goalIdx = 0
    LP.taskDone = Not CurStep()->isTask
    LP.feedback = ""
    LP.feedbackKind = 0
    LP.replyPending = False
    LP.engineReply = False
    LP.playerMoves = 0
    LP.hintShown = False
    '' The player's side is at the bottom (Black only in Black-to-move tasks).
    LP.flipped = CurStep()->isTask AndAlso LP.legalPos AndAlso CBool(LP.pos.sideToMove = SIDE_BLACK)
End Sub

Sub LessonPlay_Start(ByVal index As Integer)
    LP.index = index
    LP.finished = False
    LearnDlg.active = False
    StartStep(0)
End Sub

Private Sub SetFeedback(ByRef text As Const String, ByVal kind As Integer)
    LP.feedback = text
    LP.feedbackKind = kind
End Sub

Private Sub TaskSucceeded()
    LP.taskDone = True
    Dim As LessonStep Ptr st = CurStep()
    SetFeedback(IIf(st->success <> "", st->success, "Well done!"), 2)
    Audio_Play(SND_SOLVED)
End Sub

'' The player made move m in the current task.
Private Sub HandleTaskMove(ByRef m As ChessMove)
    Dim As LessonStep Ptr st = CurStep()
    Dim As Integer kind = st->goalKind(LP.goalIdx)
    Dim As String arg = st->goalArg(LP.goalIdx)
    If kind = GOAL_PLAYMATE OrElse kind = GOAL_PLAYPROMOTE Then
        Pos_MakeMove(LP.pos, m)
        BC_AnimateMove(LearnBC, LP.pos, m)
        LP.playerMoves += 1
        Dim As Boolean mate = Pos_InCheck(LP.pos) AndAlso Not Pos_HasLegalMove(LP.pos)
        If (kind = GOAL_PLAYMATE AndAlso mate) OrElse (kind = GOAL_PLAYPROMOTE AndAlso m.promotion <> PT_NONE) Then
            TaskSucceeded()
        ElseIf Not Pos_HasLegalMove(LP.pos) Then
            SetFeedback("Oh no - that is STALEMATE, a draw! The king had no move but was not in check. Press 'Try again'.", 1)
            LP.taskDone = False
            LP.goalIdx = -1                       '' task over, must retry
        ElseIf Pos_IsInsufficientMaterial(LP.pos) Then
            SetFeedback("Now nobody can give checkmate any more - a draw. Press 'Try again'.", 1)
            LP.goalIdx = -1
        ElseIf LP.playerMoves >= ValInt(arg) Then
            SetFeedback("You have used all " & arg & " moves. Press 'Try again' and see if you can do it faster!", 1)
            LP.goalIdx = -1
        Else
            SetFeedback("Good. " & (ValInt(arg) - LP.playerMoves) & " moves left. The computer is thinking...", 0)
            LP.engineReply = True
            LP.thinkStart = Timer
        End If
        Exit Sub
    End If

    If Lesson_GoalMet(kind, arg, LP.pos, m) Then
        Pos_MakeMove(LP.pos, m)
        BC_AnimateMove(LearnBC, LP.pos, m)
        If st->goalReply(LP.goalIdx) <> "" Then
            Dim As String e
            If Notation_ParseSAN(LP.pos, st->goalReply(LP.goalIdx), LP.replyMove, e) Then
                LP.replyPending = True
                LP.replyAt = Timer + 0.7
                SetFeedback("Good move! Now watch the reply...", 2)
            End If
        End If
        LP.goalIdx += 1
        If LP.goalIdx >= st->goalCount AndAlso Not LP.replyPending Then TaskSucceeded()
    Else
        Dim As String san = Notation_MoveToSAN(LP.pos, m)
        Dim As String fbMsg = Lesson_Feedback(*st, san)
        If fbMsg = "" Then fbMsg = st->wrong
        If fbMsg = "" Then fbMsg = "Not quite - " & san & " is not what we are looking for here. Try again!"
        SetFeedback(fbMsg, 1)
        Audio_Play(SND_ILLEGAL)
    End If
End Sub

Private Sub UpdateLessonTask()
    Dim As LessonStep Ptr st = CurStep()
    '' Scripted reply
    If LP.replyPending AndAlso CBool(Timer >= LP.replyAt) AndAlso Not BC_Busy(LearnBC) Then
        LP.replyPending = False
        Pos_MakeMove(LP.pos, LP.replyMove)
        BC_AnimateMove(LearnBC, LP.pos, LP.replyMove)
        If LP.goalIdx >= st->goalCount Then
            TaskSucceeded()
        Else
            SetFeedback("Your turn again: " & Lesson_GoalText(st->goalKind(LP.goalIdx), st->goalArg(LP.goalIdx)), 0)
        End If
    End If
    '' Computer reply in "play it out" tasks
    If LP.engineReply AndAlso Not BC_Busy(LearnBC) Then
        If Not Engine_IsThinking() Then
            Dim As EngineParams prm
            Engine_LevelParams(LEVEL_ADVANCED, STYLE_DEFENSIVE, prm)
            prm.timeLimitMs = 500 : prm.bookPlies = 0 : prm.minThinkMs = 300
            Engine_StartAsync(LP.pos, prm)
        End If
        Dim As EngineResult res
        If Engine_PollAsync(res) Then
            LP.engineReply = False
            Pos_MakeMove(LP.pos, res.bestMove)
            BC_AnimateMove(LearnBC, LP.pos, res.bestMove)
            If Not Pos_HasLegalMove(LP.pos) Then
                SetFeedback("The game has ended in a draw. Press 'Try again'.", 1)
                LP.goalIdx = -1
            Else
                SetFeedback("Your move. " & Lesson_GoalText(st->goalKind(LP.goalIdx), st->goalArg(LP.goalIdx)), 0)
            End If
        End If
    End If
End Sub

Function LessonPlay_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_LESSON
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    Dim As Lesson Ptr L = CurLesson()
    If L = 0 Then Return SCREEN_LESSONS
    Dim As LessonStep Ptr st = CurStep()
    UI.blockInput = LearnDlg.active
    UI_DrawBackground()
    Screen_DrawHeader("Learn Chess - " & L->chapter)

    If st->isTask AndAlso Not LP.taskDone Then UpdateLessonTask()

    '' Board (player's side at the bottom)
    Dim As Integer px = LayoutBoard(LP.flipped)
    Dim As BoardMarks extra
    Board_ClearMarks(extra)
    Lesson_GetMarks(*st, extra.highlight(), extra.arrowFrom(), extra.arrowTo(), extra.arrowColor(), extra.arrowCount)
    If st->isTask AndAlso (CBool(LP.goalIdx > 0) OrElse CBool(LP.playerMoves > 0) OrElse LP.taskDone) Then
        '' Once the task has started, the teaching marks would only confuse.
        Board_ClearMarks(extra)
    End If
    Dim As Boolean allowInput = st->isTask AndAlso Not LP.taskDone AndAlso Not LP.replyPending _
                                AndAlso Not LP.engineReply AndAlso CBool(LP.goalIdx >= 0) AndAlso LP.legalPos
    Dim As ChessMove m
    Dim As String illegal
    If BC_Frame(LearnBC, LearnBoard, LP.pos, allowInput, extra, m, illegal) Then HandleTaskMove(m)
    If illegal <> "" Then SetFeedback(illegal, 1)

    '' Side panel
    Dim As Integer pw = sw - px - 16, y = 62
    Gfx_Panel(px, y, pw, sh - y - 16, 14, RGB(252, 249, 240), RGB(150, 120, 80))
    Dim As Integer tx = px + 18, tw = pw - 36
    Dim As Integer ts = 26
    Do While ts > 18 AndAlso Text_Width(L->title, ts) > tw
        ts -= 1
    Loop
    Text_Draw(tx, y + 14, L->title, ts, RGB(80, 52, 24))
    Text_Draw(tx, y + 48, "Step " & (LP.stepIdx + 1) & " of " & L->stepCount & IIf(st->isTask, "  -  Your turn!", ""), _
              18, IIf(st->isTask, RGB(52, 100, 170), RGB(130, 110, 90)))
    '' Step progress dots
    Dim As Integer d
    For d = 0 To L->stepCount - 1
        Gfx_FillCircle(tx + pw - 60 - (L->stepCount - 1 - d) * 16, y + 58, 5, _
                       IIf(d <= LP.stepIdx, RGB(52, 120, 206), RGB(200, 200, 205)))
    Next

    '' Text (auto-fitted)
    Dim As Integer btnTop = sh - 16 - 3 * 52
    Dim As Integer fbH = IIf(LP.feedback <> "" OrElse st->isTask, 120, 0)
    Dim As Integer textTop = y + 82, textH = btnTop - 14 - fbH - textTop
    Dim As Integer size = Text_FitSize(st->text, tw, textH, 24, 15)
    Text_DrawWrapped(tx, textTop, tw, st->text, size, RGB(40, 34, 26))

    '' Feedback / goal box
    If fbH > 0 Then
        Dim As Integer fy = btnTop - 10 - fbH
        Dim As String fbMsg = LP.feedback
        Dim As ULong fill = RGB(236, 244, 255), border = RGB(120, 150, 200), txtC = RGB(30, 60, 110)
        If fbMsg = "" Then fbMsg = Lesson_GoalText(st->goalKind(0), st->goalArg(0))
        If LP.feedbackKind = 1 Then fill = RGB(255, 236, 228) : border = RGB(210, 110, 80) : txtC = RGB(140, 40, 20)
        If LP.feedbackKind = 2 Then fill = RGB(232, 248, 232) : border = RGB(100, 170, 100) : txtC = RGB(30, 90, 30)
        Gfx_Panel(tx - 6, fy, tw + 12, fbH, 10, fill, border, False)
        Dim As Integer fs = Text_FitSize(fbMsg, tw - 12, fbH - 16, 20, 14)
        Text_DrawWrapped(tx + 2, fy + 8, tw - 12, fbMsg, fs, txtC)
    End If

    '' Buttons
    Dim As Integer bw = (tw - 10) \ 2, bh = 44
    Dim As Integer by1 = btnTop, by2 = btnTop + 52, by3 = btnTop + 104
    If UI_Button("lp.prev", tx, by1, bw, bh, "< Previous", LP.stepIdx > 0, "Go back one step.") Then
        StartStep(LP.stepIdx - 1)
    End If
    Dim As Boolean lastStep = (LP.stepIdx = L->stepCount - 1)
    Dim As Boolean canNext = LP.taskDone
    If UI_Button("lp.next", tx + bw + 10, by1, bw, bh, IIf(lastStep, "Finish", "Next >"), canNext, _
                 IIf(canNext, "Continue the lesson.", "Solve the task first - or ask for a hint!"), BTN_PRIMARY) _
       OrElse (canNext AndAlso CBool(UI.keyCode = KEY_ENTER) AndAlso Not LearnDlg.active) Then
        If lastStep Then
            Progress_SetLessonDone(L->id)
            Progress_Save()
            App_CheckAchievements()
            Audio_Play(SND_VICTORY)
            LP.finished = True
            If LP.index + 1 < Lessons_Count() Then
                Dialog_Open(LearnDlg, "done", "Lesson complete!", "Great work! You have finished '" & L->title & _
                            "'. Ready for the next lesson: '" & Lessons_Get(LP.index + 1)->title & "'?", "Next lesson|Lesson list")
            Else
                Dialog_Open(LearnDlg, "done", "Lesson complete!", "Great work! You have finished the last lesson. " & _
                            "Now try the Chess Puzzles!", "Lesson list|Lesson list")
            End If
        Else
            StartStep(LP.stepIdx + 1)
        End If
    End If
    If UI_Button("lp.hint", tx, by2, bw, bh, "Hint", st->isTask AndAlso Not LP.taskDone AndAlso st->hint <> "", _
                 "Get a little help.") Then
        SetFeedback("Hint: " & st->hint, 0)
    End If
    If UI_Button("lp.retry", tx + bw + 10, by2, bw, bh, "Try again", st->isTask, "Start this task again.") Then
        StartStep(LP.stepIdx)
    End If
    Dim As Boolean leave = UI_Button("lp.list", tx, by3, tw, bh, "Lesson list", True, "Choose another lesson.")
    If UI.keyCode = KEY_ESCAPE AndAlso Not LearnDlg.active Then leave = True
    If leave Then
        Engine_StopAsync()
        nextScreen = SCREEN_LESSONS
    End If

    If LearnDlg.active Then
        Dim As Integer r = Dialog_Run(LearnDlg)
        If r >= 0 Then
            If r = 0 AndAlso LP.index + 1 < Lessons_Count() Then
                LessonPlay_Start(LP.index + 1)
            Else
                nextScreen = SCREEN_LESSONS
            End If
        End If
    End If
    Return nextScreen
End Function

'' =====================================================================
'' Puzzle list
'' =====================================================================
Dim Shared PLCategory As Integer = -1       '' -1 = all
Dim Shared PLScroll As Integer = 0

Declare Sub PuzzlePlay_Start(ByVal index As Integer)

Private Function InCategory(ByVal i As Integer) As Boolean
    If PLCategory < 0 Then Return True
    Return Puzzles_Get(i)->category = Puzzles_CategoryName(PLCategory)
End Function

Private Function NextUnsolved(ByVal after As Integer) As Integer
    Dim As Integer k, n = Puzzles_Count()
    For k = 1 To n
        Dim As Integer i = (after + k) Mod n
        If InCategory(i) AndAlso Not Progress_IsPuzzleSolved(Puzzles_Get(i)->id) Then Return i
    Next
    Return -1
End Function

Function PuzzleList_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_PUZZLES
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    UI_DrawBackground()
    Screen_DrawHeader("Chess Puzzles")
    If Puzzles_Count() = 0 Then
        Text_DrawWrapped(40, 120, sw - 80, "No puzzles were found. The puzzle files belong in " & ExePath() & _
                         "/data/puzzles.", 24, RGB(240, 220, 200))
    Else
        Text_Draw(24, 62, "Solved: " & PuzzlesSolvedHere() & " of " & Puzzles_Count(), 22, RGB(240, 230, 210))
    End If

    '' Categories
    Dim As Integer cx = 24, cw = 260, cy = 98, c, ch = 40
    If Puzzles_Count() > 0 AndAlso UI_Button("pl.all", cx, cy, cw, ch - 6, "All puzzles", True, "", IIf(PLCategory < 0, BTN_PRIMARY, BTN_MENU)) Then
        PLCategory = -1 : PLScroll = 0
    End If
    For c = 0 To Puzzles_CategoryCount() - 1
        If UI_Button("pl.c" & c, cx, cy + (c + 1) * ch, cw, ch - 6, Puzzles_CategoryName(c), True, "", _
                     IIf(c = PLCategory, BTN_PRIMARY, BTN_MENU)) Then
            PLCategory = c : PLScroll = 0
        End If
    Next

    '' Puzzles
    Dim As Integer lx = cx + cw + 20, lw = sw - lx - 24, ly = 98, rowH = 52
    Dim As Integer visible = (sh - 96 - ly) \ rowH
    Dim As Integer ids(0 To 255), n = 0, i
    For i = 0 To Puzzles_Count() - 1
        If InCategory(i) AndAlso n < 256 Then ids(n) = i : n += 1
    Next
    If UI_Hover(lx, ly, lw, visible * rowH) AndAlso UI.wheelDelta <> 0 Then PLScroll -= UI.wheelDelta * 2
    If PLScroll > n - visible Then PLScroll = n - visible
    If PLScroll < 0 Then PLScroll = 0
    For i = PLScroll To PLScroll + visible - 1
        If i >= n Then Exit For
        Dim As Puzzle Ptr pz = Puzzles_Get(ids(i))
        Dim As Integer y = ly + (i - PLScroll) * rowH
        If UI_Button("pl.p" & ids(i), lx, y, lw, rowH - 8, "", True, pz->category & " - difficulty " & pz->level & " of 5", BTN_MENU) Then
            PuzzlePlay_Start(ids(i))
            nextScreen = SCREEN_PUZZLE
        End If
        Text_Draw(lx + 14, y + 11, pz->title, 20, RGB(70, 46, 22))
        Text_Draw(lx + lw - 240, y + 13, pz->category, 16, RGB(130, 110, 90))
        '' Difficulty stars
        Dim As Integer k
        For k = 1 To 5
            Gfx_FillCircle(lx + lw - 90 + k * 11, y + (rowH - 8) \ 2, 4, IIf(k <= pz->level, RGB(230, 160, 20), RGB(210, 210, 210)))
        Next
        If Progress_IsPuzzleSolved(pz->id) Then
            Gfx_DoneBadge(lx + lw - 112, y + (rowH - 8) \ 2, 11)
        End If
    Next

    Dim As Integer nu = NextUnsolved(-1)
    If UI_Button("pl.next", sw - 284, sh - 64, 260, 46, "Next unsolved puzzle", nu >= 0, _
                 IIf(nu >= 0, "Jump to a puzzle you have not solved yet.", "You have solved them all!"), BTN_PRIMARY) Then
        PuzzlePlay_Start(nu)
        nextScreen = SCREEN_PUZZLE
    End If
    Dim As Boolean goBack = UI_Button("pl.back", 20, sh - 64, 140, 46, "< Back", True, "Return to the main menu.")
    If UI.keyCode = KEY_ESCAPE Then goBack = True
    If goBack Then nextScreen = SCREEN_MENU
    Return nextScreen
End Function

'' =====================================================================
'' Puzzle player
'' =====================================================================
Type PuzzlePlayState
    index        As Integer
    pos          As Position
    k            As Integer          '' index of the next solution move
    solved       As Boolean
    revealed     As Boolean          '' "Show solution" was used
    counted      As Boolean          '' attempt counted
    hintLevel    As Integer
    feedback     As String
    feedbackKind As Integer
    replyAt      As Double
    replyPending As Boolean
    showing      As Boolean          '' playing the solution automatically
    playerSide   As Integer
End Type
Dim Shared PP As PuzzlePlayState

Private Sub PPSet(ByRef text As Const String, ByVal kind As Integer)
    PP.feedback = text
    PP.feedbackKind = kind
End Sub

Sub PuzzlePlay_Start(ByVal index As Integer)
    PP.index = index
    Dim As Puzzle Ptr pz = Puzzles_Get(index)
    Dim As String e
    Pos_LoadFEN(PP.pos, pz->fen, e)
    PP.k = 0
    PP.solved = False
    PP.revealed = False
    PP.counted = False
    PP.hintLevel = 0
    PP.replyPending = False
    PP.showing = False
    PP.playerSide = PP.pos.sideToMove
    BC_Reset(LearnBC)
    PPSet(Puzzle_Instruction(*pz, PP.pos.sideToMove), 0)
End Sub

Private Sub CountAttempt()
    If PP.counted Then Exit Sub
    PP.counted = True
    Progress_AddPuzzleAttempt(Puzzles_Get(PP.index)->id)
    Progress_Save()
End Sub

Private Sub PuzzleSolved()
    Dim As Puzzle Ptr pz = Puzzles_Get(PP.index)
    PP.solved = True
    CountAttempt()
    If Not PP.revealed Then
        Progress_SetPuzzleSolved(pz->id)
        Progress_Save()
        Audio_Play(SND_SOLVED)
        App_CheckAchievements()
        PPSet("Correct! " & pz->explain, 2)
    Else
        PPSet(pz->explain, 0)
    End If
End Sub

'' Plays the next solution move (used by replies and "Show solution").
Private Sub PlaySolutionMove()
    Dim As Puzzle Ptr pz = Puzzles_Get(PP.index)
    Dim As ChessMove m
    Dim As String e
    If PP.k >= Puzzle_MoveCount(*pz) Then Exit Sub
    If Not Notation_ParseSAN(PP.pos, Puzzle_Move(*pz, PP.k), m, e) Then Exit Sub
    Pos_MakeMove(PP.pos, m)
    BC_AnimateMove(LearnBC, PP.pos, m)
    PP.k += 1
    If PP.k >= Puzzle_MoveCount(*pz) Then PuzzleSolved()
End Sub

Function PuzzlePlay_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_PUZZLE
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    Dim As Puzzle Ptr pz = Puzzles_Get(PP.index)
    If pz = 0 Then Return SCREEN_PUZZLES
    UI_DrawBackground()
    Screen_DrawHeader("Chess Puzzles - " & pz->category)

    '' Opponent replies / automatic solution
    If (PP.replyPending OrElse PP.showing) AndAlso CBool(Timer >= PP.replyAt) AndAlso Not BC_Busy(LearnBC) AndAlso Not PP.solved Then
        PP.replyPending = False
        PlaySolutionMove()
        PP.replyAt = Timer + 0.9
        If PP.showing AndAlso PP.solved Then PP.showing = False
    End If

    Dim As Integer px = LayoutBoard(PP.playerSide = SIDE_BLACK)
    Dim As BoardMarks extra
    Board_ClearMarks(extra)
    If PP.hintLevel >= 2 AndAlso Not PP.solved Then
        Dim As ChessMove hm
        Dim As String e
        If Notation_ParseSAN(PP.pos, Puzzle_Move(*pz, PP.k), hm, e) Then extra.highlight(hm.fromSq) = MARK_BLUE
    End If
    Dim As Boolean allowInput = Not PP.solved AndAlso Not PP.replyPending AndAlso Not PP.showing
    Dim As ChessMove m
    Dim As String illegal
    If BC_Frame(LearnBC, LearnBoard, PP.pos, allowInput, extra, m, illegal) Then
        Select Case Puzzle_Judge(*pz, PP.k, PP.pos, m)
        Case PV_SOLVED
            Pos_MakeMove(PP.pos, m)
            BC_AnimateMove(LearnBC, PP.pos, m)
            PP.k = Puzzle_MoveCount(*pz)
            PuzzleSolved()
        Case PV_CORRECT
            Pos_MakeMove(PP.pos, m)
            BC_AnimateMove(LearnBC, PP.pos, m)
            PP.k += 1
            PP.replyPending = True
            PP.replyAt = Timer + 0.7
            PPSet("Good move! Keep going...", 2)
        Case Else
            CountAttempt()
            Audio_Play(SND_ILLEGAL)
            PPSet(Notation_MoveToSAN(PP.pos, m) & " is not the best move here. Try again!", 1)
        End Select
    End If
    If illegal <> "" Then PPSet(illegal, 1)

    '' Side panel
    Dim As Integer pw = sw - px - 16, y = 62
    Gfx_Panel(px, y, pw, sh - y - 16, 14, RGB(252, 249, 240), RGB(150, 120, 80))
    Dim As Integer tx = px + 18, tw = pw - 36
    Text_Draw(tx, y + 14, pz->title, 26, RGB(80, 52, 24))
    Text_Draw(tx, y + 50, pz->category, 18, RGB(130, 110, 90))
    Dim As Integer k
    For k = 1 To 5
        Gfx_FillCircle(tx + tw - 70 + k * 13, y + 60, 5, IIf(k <= pz->level, RGB(230, 160, 20), RGB(210, 210, 210)))
    Next
    If Progress_IsPuzzleSolved(pz->id) Then Text_Draw(tx, y + 76, "You have solved this puzzle before.", 16, RGB(40, 130, 60))

    '' Turn indicator
    Gfx_FillCircle(tx + 16, y + 118, 14, RGB(60, 60, 60))
    Gfx_FillCircle(tx + 16, y + 118, 12, IIf(PP.playerSide = SIDE_WHITE, RGB(250, 250, 245), RGB(30, 30, 34)))
    Text_Draw(tx + 40, y + 106, "You play " & IIf(PP.playerSide = SIDE_WHITE, "White", "Black"), 22, RGB(40, 34, 28))

    '' Feedback
    Dim As Integer btnTop = sh - 16 - 3 * 52
    Dim As Integer fy = y + 150, fh = btnTop - 14 - fy
    Dim As ULong fill = RGB(236, 244, 255), border = RGB(120, 150, 200), txtC = RGB(30, 60, 110)
    If PP.feedbackKind = 1 Then fill = RGB(255, 236, 228) : border = RGB(210, 110, 80) : txtC = RGB(140, 40, 20)
    If PP.feedbackKind = 2 Then fill = RGB(232, 248, 232) : border = RGB(100, 170, 100) : txtC = RGB(30, 90, 30)
    Gfx_Panel(tx - 6, fy, tw + 12, fh, 10, fill, border, False)
    Dim As String fbText = PP.feedback
    If PP.hintLevel >= 1 AndAlso Not PP.solved AndAlso PP.feedbackKind <> 1 Then fbText &= "|Hint: " & pz->hint
    Dim As Integer fs = Text_FitSize(fbText, tw - 12, fh - 16, 22, 14)
    Text_DrawWrapped(tx + 2, fy + 8, tw - 12, fbText, fs, txtC)

    '' Buttons
    Dim As Integer bw = (tw - 10) \ 2, bh = 44
    Dim As Integer by1 = btnTop, by2 = btnTop + 52, by3 = btnTop + 104
    If UI_Button("pp.hint", tx, by1, bw, bh, IIf(PP.hintLevel = 0, "Hint", "More help"), Not PP.solved AndAlso PP.hintLevel < 2, _
                 "First a tip, then the piece to move is marked.") Then
        PP.hintLevel += 1
        If PP.hintLevel = 1 Then PPSet(Puzzle_Instruction(*pz, PP.playerSide), 0)
        If PP.hintLevel = 2 Then PPSet("The piece to move is marked in blue.", 0)
    End If
    If UI_Button("pp.show", tx + bw + 10, by1, bw, bh, "Show solution", Not PP.solved AndAlso Not PP.showing, _
                 "Watch the solution (the puzzle will not count as solved).") Then
        CountAttempt()
        PP.revealed = True
        PP.showing = True
        PP.replyAt = Timer
        PPSet("Watch the solution...", 0)
    End If
    If UI_Button("pp.retry", tx, by2, bw, bh, "Try again", True, "Start this puzzle again.") Then
        PuzzlePlay_Start(PP.index)
    End If
    Dim As Integer nu = NextUnsolved(PP.index)
    If nu < 0 Then nu = (PP.index + 1) Mod Puzzles_Count()
    If UI_Button("pp.next", tx + bw + 10, by2, bw, bh, "Next puzzle", True, "Go to the next puzzle.", _
                 IIf(PP.solved, BTN_PRIMARY, BTN_NORMAL)) OrElse (PP.solved AndAlso CBool(UI.keyCode = KEY_ENTER)) Then
        PuzzlePlay_Start(nu)
    End If
    Dim As Boolean leave = UI_Button("pp.list", tx, by3, tw, bh, "Puzzle list", True, "Choose another puzzle.")
    If UI.keyCode = KEY_ESCAPE Then leave = True
    If leave Then nextScreen = SCREEN_PUZZLES
    Return nextScreen
End Function

'' Debug/screenshot helpers
Sub Learn_DebugLesson(ByRef id As Const String, ByVal stepIdx As Integer)
    Dim As Integer i = Lessons_Find(id)
    If i < 0 Then Exit Sub
    LessonPlay_Start(i)
    If stepIdx > 0 Then StartStep(stepIdx)
End Sub

Sub Learn_DebugPuzzle(ByRef id As Const String, ByVal hintLevel As Integer)
    Dim As Integer i = Puzzles_Find(id)
    If i < 0 Then Exit Sub
    PuzzlePlay_Start(i)
    PP.hintLevel = hintLevel
End Sub

'' Renders every lesson step and every puzzle once (automated check for
'' layout/runtime problems). Returns the number of frames drawn.
Function Learn_RenderAll() As Integer
    Dim As Integer i, j, frames = 0
    For i = 0 To Lessons_Count() - 1
        LessonPlay_Start(i)
        For j = 0 To Lessons_Get(i)->stepCount - 1
            StartStep(j)
            UI_BeginFrame() : LessonPlay_Frame() : UI_EndFrame()
            frames += 1
        Next
    Next
    For i = 0 To Puzzles_Count() - 1
        PuzzlePlay_Start(i)
        PP.hintLevel = 2
        UI_BeginFrame() : PuzzlePlay_Frame() : UI_EndFrame()
        frames += 1
    Next
    Return frames
End Function
