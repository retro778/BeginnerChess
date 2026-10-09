'' =====================================================================
'' BeginnerChess - lessons.bas
'' See lessons.bi.
'' =====================================================================
#include once "lessons.bi"
#include once "dir.bi"

Dim Shared LessonList() As Lesson
Dim Shared LessonCount As Integer = 0
Dim Shared ChapterNames(0 To 31) As String
Dim Shared ChapterCount As Integer = 0

Function Lessons_Count() As Integer
    Return LessonCount
End Function

Function Lessons_Get(ByVal index As Integer) As Lesson Ptr
    If index < 0 OrElse index >= LessonCount Then Return 0
    Return @LessonList(index)
End Function

Function Lessons_Find(ByRef id As Const String) As Integer
    Dim As Integer i
    For i = 0 To LessonCount - 1
        If LessonList(i).id = id Then Return i
    Next
    Return -1
End Function

Function Lessons_ChapterCount() As Integer
    Return ChapterCount
End Function

Function Lessons_ChapterName(ByVal index As Integer) As String
    If index < 0 OrElse index >= ChapterCount Then Return ""
    Return ChapterNames(index)
End Function

Private Function ColorId(ByRef w As Const String) As Integer
    Select Case LCase(w)
    Case "green" : Return 1
    Case "red"   : Return 2
    Case "blue"  : Return 3
    Case "yellow": Return 4
    End Select
    Return 0
End Function

'' Splits "word rest" into the first word and the remainder.
Private Sub FirstWord(ByRef s As Const String, ByRef w As String, ByRef rest As String)
    Dim As String t = Trim(s)
    Dim As Integer sp = InStr(t, " ")
    If sp = 0 Then
        w = t : rest = ""
    Else
        w = Left(t, sp - 1) : rest = Trim(Mid(t, sp + 1))
    End If
End Sub

Function Lessons_LoadFile(ByRef fileName As Const String, ByRef errors As String) As Integer
    Dim As Integer f = FreeFile
    If Open(fileName For Input As #f) <> 0 Then
        errors &= "Cannot open " & fileName & Chr(10)
        Return 0
    End If
    Dim As Integer loaded = 0, lineNo = 0
    Dim As Lesson Ptr cur = 0
    Dim As LessonStep Ptr st = 0
    Dim As String ln, kw, rest
    Do While Not EOF(f)
        Line Input #f, ln
        lineNo += 1
        ln = Trim(ln, Any " " & Chr(9, 13))
        If ln = "" OrElse Left(ln, 1) = "#" Then Continue Do
        FirstWord(ln, kw, rest)
        kw = UCase(kw)
        Dim As String where = fileName & " line " & lineNo & ": "
        If kw = "LESSON" Then
            If LessonCount > UBound(LessonList) Then ReDim Preserve LessonList(0 To LessonCount * 2 + 15)
            cur = @LessonList(LessonCount)
            cur->id = rest
            cur->title = rest
            cur->chapter = "Lessons"
            cur->summary = ""
            cur->stepCount = 0
            st = 0
            LessonCount += 1
            loaded += 1
            Continue Do
        End If
        If cur = 0 Then
            errors &= where & "text outside a LESSON" & Chr(10)
            Continue Do
        End If
        Select Case kw
        Case "TITLE"   : cur->title = rest
        Case "SUMMARY" : cur->summary = rest
        Case "CHAPTER"
            cur->chapter = rest
            Dim As Integer c, found = 0
            For c = 0 To ChapterCount - 1
                If ChapterNames(c) = rest Then found = 1
            Next
            If found = 0 AndAlso ChapterCount < 32 Then ChapterNames(ChapterCount) = rest : ChapterCount += 1
        Case "PAGE", "TASK"
            If cur->stepCount >= LESSON_MAX_STEPS Then
                errors &= where & "too many steps" & Chr(10)
                st = 0
            Else
                st = @cur->steps(cur->stepCount)
                cur->stepCount += 1
                st->isTask = (kw = "TASK")
                st->fen = "" : st->playMoves = "" : st->text = "" : st->highlights = "" : st->arrows = ""
                st->hint = "" : st->success = "" : st->wrong = "" : st->feedback = ""
                st->goalCount = 0
            End If
        Case "END"
            cur = 0 : st = 0
        Case Else
            If st = 0 Then
                errors &= where & kw & " before PAGE/TASK" & Chr(10)
                Continue Do
            End If
            Select Case kw
            Case "FEN"     : st->fen = rest
            Case "PLAY"    : st->playMoves &= " " & rest
            Case "TEXT"    : st->text &= IIf(st->text = "" OrElse Right(st->text, 1) = "|", "", " ") & rest
            Case "HINT"    : st->hint = rest
            Case "SUCCESS" : st->success = rest
            Case "WRONG"   : st->wrong = rest
            Case "FEEDBACK"
                Dim As String san, txt
                FirstWord(rest, san, txt)
                st->feedback &= san & Chr(1) & txt & Chr(2)
            Case "HIGHLIGHT", "ARROW"
                Dim As String w, r = rest
                Dim As Integer col = 1
                FirstWord(r, w, r)
                If ColorId(w) > 0 Then
                    col = ColorId(w)
                Else
                    r = Trim(w & " " & r)
                End If
                Do While r <> ""
                    FirstWord(r, w, r)
                    If kw = "HIGHLIGHT" Then
                        st->highlights &= col & ":" & w & " "
                    Else
                        st->arrows &= col & ":" & w & " "
                    End If
                Loop
            Case "GOAL"
                If st->goalCount >= LESSON_MAX_GOALS Then
                    errors &= where & "too many goals" & Chr(10)
                    Continue Do
                End If
                Dim As String gk, ga
                FirstWord(rest, gk, ga)
                Dim As Integer kind = GOAL_NONE
                Select Case LCase(gk)
                Case "move"        : kind = GOAL_MOVE
                Case "mate"        : kind = GOAL_MATE
                Case "check"       : kind = GOAL_CHECK
                Case "capture"     : kind = GOAL_CAPTURE
                Case "castle"      : kind = GOAL_CASTLE
                Case "promote"     : kind = GOAL_PROMOTE
                Case "any"         : kind = GOAL_ANY
                Case "piece"       : kind = GOAL_PIECE
                Case "safe"        : kind = GOAL_SAFE
                Case "best"        : kind = GOAL_BEST
                Case "playmate"    : kind = GOAL_PLAYMATE
                Case "playpromote" : kind = GOAL_PLAYPROMOTE
                End Select
                If kind = GOAL_NONE Then
                    errors &= where & "unknown goal '" & gk & "'" & Chr(10)
                Else
                    st->goalKind(st->goalCount) = kind
                    st->goalArg(st->goalCount) = ga
                    st->goalReply(st->goalCount) = ""
                    st->goalCount += 1
                End If
            Case "REPLY"
                If st->goalCount = 0 Then
                    errors &= where & "REPLY before GOAL" & Chr(10)
                Else
                    st->goalReply(st->goalCount - 1) = rest
                End If
            Case Else
                errors &= where & "unknown keyword " & kw & Chr(10)
            End Select
        End Select
    Loop
    Close #f
    Return loaded
End Function

Function Lessons_LoadFolder(ByRef folder As Const String, ByRef errors As String) As Integer
    Erase LessonList
    ReDim LessonList(0 To 31)
    LessonCount = 0
    ChapterCount = 0
    '' Collect and sort file names so chapters come in a fixed order.
    Dim As String files(0 To 63)
    Dim As Integer n = 0, i, j
    Dim As String f = Dir(folder & "/*.txt", fbNormal)
    Do While f <> "" AndAlso n < 64
        files(n) = f : n += 1
        f = Dir()
    Loop
    For i = 0 To n - 2
        For j = i + 1 To n - 1
            If files(j) < files(i) Then Swap files(i), files(j)
        Next
    Next
    For i = 0 To n - 1
        Lessons_LoadFile(folder & "/" & files(i), errors)
    Next
    If n = 0 Then errors &= "No lesson files found in " & folder & Chr(10)
    Return LessonCount
End Function

Function Lesson_StepPosition(ByRef st As LessonStep, ByRef p As Position, ByRef isLegal As Boolean, _
                             ByRef errMsg As String) As Boolean
    errMsg = ""
    If Not Lesson_LoadPosition(st.fen, p, isLegal) Then
        errMsg = "bad FEN '" & st.fen & "'"
        Return False
    End If
    Dim As String r = Trim(st.playMoves), w
    If r <> "" AndAlso Not isLegal Then
        errMsg = "PLAY needs a legal FEN"
        Return False
    End If
    Do While r <> ""
        FirstWord(r, w, r)
        Dim As ChessMove m
        Dim As String why
        If Not Notation_ParseSAN(p, w, m, why) Then
            errMsg = "PLAY move '" & w & "': " & why
            Return False
        End If
        Pos_MakeMove(p, m)
    Loop
    Return True
End Function

Function Lesson_LoadPosition(ByRef fen As Const String, ByRef p As Position, ByRef isLegal As Boolean) As Boolean
    Dim As String errMsg
    isLegal = False
    Dim As String f = Trim(fen)
    If LCase(f) = "start" OrElse f = "" Then f = START_FEN
    If Pos_LoadFEN(p, f, errMsg) Then
        isLegal = True
        Return True
    End If
    '' Display-only: place the pieces without checking the rules.
    Pos_Clear(p)
    Dim As String placement = f
    Dim As Integer sp = InStr(placement, " ")
    If sp > 0 Then placement = Left(placement, sp - 1)
    Dim As Integer rank = 7, file = 0, i
    For i = 1 To Len(placement)
        Dim As String c = Mid(placement, i, 1)
        If c = "/" Then
            rank -= 1 : file = 0
            If rank < 0 Then Return False
        ElseIf c >= "1" AndAlso c <= "8" Then
            file += Val(c)
        Else
            Dim As Integer k = InStr("PNBRQKpnbrqk", c)
            If k = 0 OrElse file > 7 Then Return False
            p.board(MAKE_SQ(file, rank)) = MAKE_PIECE(IIf(k > 6, SIDE_BLACK, SIDE_WHITE), ((k - 1) Mod 6) + 1)
            file += 1
        End If
    Next
    Return rank = 0
End Function

Sub Lesson_GetMarks(ByRef st As LessonStep, highlight() As UByte, arrowFrom() As Integer, _
                    arrowTo() As Integer, arrowColor() As Integer, ByRef arrowCount As Integer)
    Dim As Integer i
    For i = 0 To 127 : highlight(i) = 0 : Next
    arrowCount = 0
    Dim As String r = st.highlights, w
    Do While r <> ""
        FirstWord(r, w, r)
        Dim As Integer c = InStr(w, ":")
        If c > 0 Then
            Dim As Integer sq = Sq_Parse(Mid(w, c + 1))
            If sq <> NO_SQUARE Then highlight(sq) = ValInt(Left(w, c - 1))
        End If
    Loop
    r = st.arrows
    Do While r <> ""
        FirstWord(r, w, r)
        Dim As Integer c = InStr(w, ":")
        If c > 0 AndAlso arrowCount <= UBound(arrowFrom) Then
            Dim As String mv = Mid(w, c + 1)
            Dim As Integer a = Sq_Parse(Left(mv, 2)), b = Sq_Parse(Mid(mv, 3, 2))
            If a <> NO_SQUARE AndAlso b <> NO_SQUARE Then
                arrowFrom(arrowCount) = a : arrowTo(arrowCount) = b
                arrowColor(arrowCount) = ValInt(Left(w, c - 1))
                arrowCount += 1
            End If
        End If
    Loop
End Sub

'' True if the side to move has a move that checkmates at once.
Private Function HasMateInOne(ByRef p As Position) As Boolean
    Dim As MoveList list
    Pos_GenerateLegal(p, list)
    Dim As Integer i
    For i = 0 To list.count - 1
        Pos_MakeMove(p, list.moves(i))
        Dim As Boolean mate = Pos_InCheck(p) AndAlso Not Pos_HasLegalMove(p)
        Pos_UnmakeMove(p)
        If mate Then Return True
    Next
    Return False
End Function

Function Lesson_GoalMet(ByVal kind As Integer, ByRef arg As Const String, ByRef p As Position, _
                        ByRef m As ChessMove) As Boolean
    Select Case kind
    Case GOAL_ANY, GOAL_PLAYMATE, GOAL_PLAYPROMOTE
        Return True
    Case GOAL_MOVE
        Dim As String san = Notation_MoveToSAN(p, m), r = Trim(arg), w
        '' Compare without + and # so the file need not get them exactly right.
        Do While Right(san, 1) = "+" OrElse Right(san, 1) = "#" : san = Left(san, Len(san) - 1) : Loop
        Do While r <> ""
            FirstWord(r, w, r)
            Do While Right(w, 1) = "+" OrElse Right(w, 1) = "#" : w = Left(w, Len(w) - 1) : Loop
            If w = san Then Return True
        Loop
        Return False
    Case GOAL_CAPTURE
        Return (m.flags And MF_CAPTURE) <> 0
    Case GOAL_CASTLE
        Return (m.flags And MF_CASTLE) <> 0
    Case GOAL_PROMOTE
        Return m.promotion <> PT_NONE
    Case GOAL_PIECE
        Return m.fromSq = Sq_Parse(Trim(arg))
    End Select

    '' Goals that look at the position after the move
    Dim As Boolean ok = False
    Select Case kind
    Case GOAL_MATE, GOAL_CHECK, GOAL_SAFE
        Pos_MakeMove(p, m)
        Select Case kind
        Case GOAL_MATE  : ok = Pos_InCheck(p) AndAlso Not Pos_HasLegalMove(p)
        Case GOAL_CHECK : ok = Pos_InCheck(p)
        Case GOAL_SAFE  : ok = Not HasMateInOne(p)
        End Select
        Pos_UnmakeMove(p)
    Case GOAL_BEST
        '' Compare with the engine's best move (fixed depth, no randomness).
        Dim As EngineParams prm
        Engine_LevelParams(LEVEL_ADVANCED, STYLE_BALANCED, prm)
        prm.maxDepth = 5 : prm.timeLimitMs = 700 : prm.bookPlies = 0
        Dim As EngineResult best, mine
        If Not Engine_Search(p, prm, best) Then Return False
        If Move_Equal(best.bestMove, m) Then Return True
        Pos_MakeMove(p, m)
        Dim As Boolean any1 = Engine_Search(p, prm, mine)
        Pos_UnmakeMove(p)
        If Not any1 Then
            '' The move ended the game: good only if it mated.
            Pos_MakeMove(p, m)
            ok = Pos_InCheck(p)
            Pos_UnmakeMove(p)
            Return ok
        End If
        Dim As Integer myScore = -mine.score
        Dim As Integer margin = IIf(Val(arg) > 0, ValInt(arg), 60)
        ok = myScore >= best.score - margin
    End Select
    Return ok
End Function

Function Lesson_GoalText(ByVal kind As Integer, ByRef arg As Const String) As String
    Select Case kind
    Case GOAL_MATE        : Return "Give checkmate!"
    Case GOAL_CHECK       : Return "Give check!"
    Case GOAL_CAPTURE     : Return "Capture a piece!"
    Case GOAL_CASTLE      : Return "Castle!"
    Case GOAL_PROMOTE     : Return "Promote a pawn!"
    Case GOAL_SAFE        : Return "Stop the checkmate!"
    Case GOAL_BEST        : Return "Find a good move!"
    Case GOAL_PLAYMATE    : Return "Checkmate the computer within " & arg & " moves!"
    Case GOAL_PLAYPROMOTE : Return "Make a new queen within " & arg & " moves!"
    Case GOAL_PIECE       : Return "Move the piece on " & arg & "."
    End Select
    Return "Make your move."
End Function

Function Lesson_Feedback(ByRef st As LessonStep, ByRef san As Const String) As String
    Dim As String s = san
    Do While Right(s, 1) = "+" OrElse Right(s, 1) = "#" : s = Left(s, Len(s) - 1) : Loop
    Dim As String r = st.feedback
    Do While r <> ""
        Dim As Integer e = InStr(r, Chr(2))
        If e = 0 Then Exit Do
        Dim As String item = Left(r, e - 1)
        r = Mid(r, e + 1)
        Dim As Integer c = InStr(item, Chr(1))
        Dim As String fs = Left(item, c - 1)
        Do While Right(fs, 1) = "+" OrElse Right(fs, 1) = "#" : fs = Left(fs, Len(fs) - 1) : Loop
        If fs = s Then Return Mid(item, c + 1)
    Loop
    Return ""
End Function
