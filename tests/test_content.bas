'' =====================================================================
'' BeginnerChess - tests/test_content.bas
'' Validates the teaching content in data/lessons and data/puzzles:
'' every position, highlight, arrow, goal, reply and puzzle solution is
'' checked with the rules, and puzzle solutions are checked with the
'' engine (is the solution really the best move?).
''
''   test_content             validate everything
''   test_content --verbose   also print the engine's view of each puzzle
'' =====================================================================
#include once "../modules/lessons.bi"
#include once "../modules/puzzles.bi"

Dim Shared TestsPassed As Integer = 0
Dim Shared TestsFailed As Integer = 0
Dim Shared Verbose As Boolean = False

Sub Check(ByVal ok As Boolean, ByRef testName As Const String, ByRef detail As Const String = "")
    If ok Then
        TestsPassed += 1
    Else
        TestsFailed += 1
        Print "  FAIL: " & testName;
        If detail <> "" Then Print "  (" & detail & ")" Else Print
    End If
End Sub

Function IsMate(ByRef p As Position) As Boolean
    Return Pos_InCheck(p) AndAlso Not Pos_HasLegalMove(p)
End Function

Sub ValidateLessons(ByRef folder As Const String)
    Print "Lessons..."
    Dim As String errors
    Dim As Integer n = Lessons_LoadFolder(folder, errors)
    Check errors = "", "lesson files parse cleanly", errors
    Check n >= 50, "at least 50 lessons", Str(n)
    Print "  " & n & " lessons in " & Lessons_ChapterCount() & " chapters"
    Static p As Position
    Dim As Integer li, si, gi, i, tasks = 0, pages = 0
    For li = 0 To n - 1
        Dim As Lesson Ptr L = Lessons_Get(li)
        Dim As String nm = L->id
        Check L->stepCount > 0, nm & ": has steps"
        Check L->title <> "" AndAlso L->chapter <> "", nm & ": has title and chapter"
        For si = 0 To L->stepCount - 1
            Dim As LessonStep Ptr st = @L->steps(si)
            Dim As String where = nm & " step " & (si + 1)
            Dim As Boolean legal
            Dim As String why
            Dim As Boolean ok = Lesson_StepPosition(*st, p, legal, why)
            Check ok, where & ": position", why
            Check st->text <> "", where & ": has text"
            '' Highlights/arrows refer to real squares.
            Dim As String r = st->highlights & st->arrows, w
            Do While Trim(r) <> ""
                r = Trim(r)
                Dim As Integer sp = InStr(r & " ", " ")
                w = Left(r, sp - 1) : r = Mid(r, sp + 1)
                Dim As String sqs = Mid(w, InStr(w, ":") + 1)
                Dim As Boolean good = (Sq_Parse(Left(sqs, 2)) <> NO_SQUARE)
                If Len(sqs) = 4 Then good = good AndAlso (Sq_Parse(Mid(sqs, 3, 2)) <> NO_SQUARE)
                If Len(sqs) <> 2 AndAlso Len(sqs) <> 4 Then good = False
                Check good, where & ": mark '" & w & "'"
            Loop
            If Not st->isTask Then
                pages += 1
                Check st->goalCount = 0, where & ": PAGE has no GOAL"
                Continue For
            End If
            tasks += 1
            Check legal, where & ": task position is legal", st->fen
            Check st->goalCount > 0, where & ": task has a GOAL"
            If Not (ok AndAlso legal) Then Continue For
            '' Play through the goals.
            For gi = 0 To st->goalCount - 1
                Dim As Integer kind = st->goalKind(gi)
                Dim As String arg = st->goalArg(gi)
                Dim As MoveList list
                Pos_GenerateLegal(p, list)
                Dim As ChessMove chosen
                Dim As Boolean found = False
                If kind = GOAL_MOVE Then
                    Dim As String rr = Trim(arg) & " "
                    Do While Trim(rr) <> ""
                        Dim As Integer sp = InStr(rr, " ")
                        Dim As String san = Left(rr, sp - 1)
                        rr = LTrim(Mid(rr, sp + 1))
                        Dim As ChessMove m
                        Dim As String e
                        If Notation_ParseSAN(p, san, m, e) Then
                            If Not found Then chosen = m : found = True
                            Check Lesson_GoalMet(kind, arg, p, m), where & ": goal accepts " & san
                        Else
                            Check False, where & ": goal move '" & san & "' is legal", e
                        End If
                    Loop
                ElseIf kind = GOAL_PLAYMATE OrElse kind = GOAL_PLAYPROMOTE Then
                    Check ValInt(arg) > 0, where & ": play goal has a move limit"
                    Check list.count > 0, where & ": play goal has moves"
                    found = False                 '' nothing to replay after this goal
                    Exit For
                Else
                    For i = 0 To list.count - 1
                        If Lesson_GoalMet(kind, arg, p, list.moves(i)) Then
                            chosen = list.moves(i) : found = True
                            Exit For
                        End If
                    Next
                    Check found, where & ": goal " & kind & " can be met"
                    If kind = GOAL_PIECE Then Check Sq_Parse(arg) <> NO_SQUARE, where & ": piece square"
                End If
                If Not found Then Exit For
                Pos_MakeMove(p, chosen)
                If st->goalReply(gi) <> "" Then
                    Dim As ChessMove rm
                    Dim As String e
                    If Notation_ParseSAN(p, st->goalReply(gi), rm, e) Then
                        Pos_MakeMove(p, rm)
                    Else
                        Check False, where & ": reply '" & st->goalReply(gi) & "' is legal", e
                        Exit For
                    End If
                End If
            Next
        Next
    Next
    Print "  " & pages & " pages, " & tasks & " tasks checked"
End Sub

Sub ValidatePuzzles(ByRef folder As Const String)
    Print "Puzzles..."
    Dim As String errors
    Dim As Integer n = Puzzles_LoadFolder(folder, errors)
    Check errors = "", "puzzle files parse cleanly", errors
    Check n >= 40, "at least 40 puzzles", Str(n)
    Print "  " & n & " puzzles in " & Puzzles_CategoryCount() & " categories"
    Static p As Position
    Dim As Integer pi, k
    For pi = 0 To n - 1
        Dim As Puzzle Ptr pz = Puzzles_Get(pi)
        Engine_NewGame()          '' each puzzle is judged on its own (no memory of earlier ones)
        Dim As String nm = pz->id
        Dim As String e
        If Not Pos_LoadFEN(p, pz->fen, e) Then
            Check False, nm & ": FEN", e
            Continue For
        End If
        Check pz->level >= 1 AndAlso pz->level <= 5, nm & ": level 1-5"
        Check pz->hint <> "" AndAlso pz->explain <> "", nm & ": hint and explanation"
        Dim As Integer total = Puzzle_MoveCount(*pz)
        Check total >= 1, nm & ": has a solution"
        Dim As Boolean allLegal = True
        For k = 0 To total - 1
            Dim As ChessMove m
            Dim As String san = Puzzle_Move(*pz, k)
            If Not Notation_ParseSAN(p, san, m, e) Then
                Check False, nm & ": solution move " & (k + 1) & " '" & san & "'", e
                allLegal = False
                Exit For
            End If
            If k Mod 2 = 0 Then
                '' The player's move: is it really the best?
                Dim As EngineParams prm
                Engine_LevelParams(LEVEL_ADVANCED, STYLE_BALANCED, prm)
                prm.maxDepth = 8 : prm.timeLimitMs = 2500 : prm.bookPlies = 0
                Dim As EngineResult best
                Engine_Search(p, prm, best)
                Dim As Integer verdict = Puzzle_Judge(*pz, k, p, m)
                Check verdict <> PV_WRONG, nm & ": solution move accepted by the judge"
                Dim As Boolean agrees = Move_Equal(best.bestMove, m)
                Dim As Integer solScore = best.score
                '' When the engine's choice is itself an accepted answer, the puzzle
                '' only needs the main move to be about as good (search noise).
                Dim As Integer margin = 40
                If Not agrees AndAlso Puzzle_Judge(*pz, k, p, best.bestMove) <> PV_WRONG Then margin = 80
                If Not agrees Then
                    Pos_MakeMove(p, m)
                    If IsMate(p) Then
                        agrees = True
                    Else
                        Dim As EngineResult after
                        prm.maxDepth = 7
                        If Engine_Search(p, prm, after) Then solScore = -after.score
                        agrees = (solScore >= best.score - margin) OrElse (solScore > SCORE_MATE - 100)
                    End If
                    Pos_UnmakeMove(p)
                End If
                Check agrees, nm & ": move " & san & " is the best (engine: " & Notation_MoveToSAN(p, best.bestMove) & _
                      " " & best.score & ")", "solution scores " & solScore
                If Verbose Then
                    Print "    " & nm & " move " & (k \ 2 + 1) & ": " & san & "  engine " & _
                          Notation_MoveToSAN(p, best.bestMove) & " (" & best.score & ", depth " & best.depth & ")"
                End If
            End If
            Pos_MakeMove(p, m)
        Next
        If allLegal AndAlso InStr(LCase(pz->category), "mate in") > 0 Then
            Check IsMate(p), nm & ": the solution ends in checkmate"
        End If
    Next
End Sub

Verbose = (Command(1) = "--verbose")
Print "BeginnerChess content tests"
Dim As String root = ExePath() & "/../data"
ValidateLessons(root & "/lessons")
ValidatePuzzles(root & "/puzzles")
Print
Print "Passed: " & TestsPassed & "   Failed: " & TestsFailed
If TestsFailed > 0 Then End 1
End 0
