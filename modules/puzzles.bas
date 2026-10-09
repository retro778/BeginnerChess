'' =====================================================================
'' BeginnerChess - puzzles.bas
'' See puzzles.bi.
'' =====================================================================
#include once "puzzles.bi"
#include once "dir.bi"

Dim Shared PuzzleList() As Puzzle
Dim Shared PuzzleCount As Integer = 0
Dim Shared CategoryNames(0 To 31) As String
Dim Shared CategoryCount As Integer = 0

Function Puzzles_Count() As Integer
    Return PuzzleCount
End Function

Function Puzzles_Get(ByVal index As Integer) As Puzzle Ptr
    If index < 0 OrElse index >= PuzzleCount Then Return 0
    Return @PuzzleList(index)
End Function

Function Puzzles_Find(ByRef id As Const String) As Integer
    Dim As Integer i
    For i = 0 To PuzzleCount - 1
        If PuzzleList(i).id = id Then Return i
    Next
    Return -1
End Function

Function Puzzles_CategoryCount() As Integer
    Return CategoryCount
End Function

Function Puzzles_CategoryName(ByVal index As Integer) As String
    If index < 0 OrElse index >= CategoryCount Then Return ""
    Return CategoryNames(index)
End Function

Private Sub AddCategory(ByRef c As Const String)
    Dim As Integer i
    For i = 0 To CategoryCount - 1
        If CategoryNames(i) = c Then Exit Sub
    Next
    If CategoryCount < 32 Then CategoryNames(CategoryCount) = c : CategoryCount += 1
End Sub

Private Function LoadPuzzleFile(ByRef fileName As Const String, ByRef errors As String) As Integer
    Dim As Integer f = FreeFile
    If Open(fileName For Input As #f) <> 0 Then
        errors &= "Cannot open " & fileName & Chr(10)
        Return 0
    End If
    Dim As Integer lineNo = 0, loaded = 0
    Dim As Puzzle Ptr cur = 0
    Dim As String ln
    Do While Not EOF(f)
        Line Input #f, ln
        lineNo += 1
        ln = Trim(ln, Any " " & Chr(9, 13))
        If ln = "" OrElse Left(ln, 1) = "#" Then Continue Do
        Dim As Integer sp = InStr(ln, " ")
        Dim As String kw = UCase(IIf(sp > 0, Left(ln, sp - 1), ln))
        Dim As String rest = IIf(sp > 0, Trim(Mid(ln, sp + 1)), "")
        If kw = "PUZZLE" Then
            If PuzzleCount > UBound(PuzzleList) Then ReDim Preserve PuzzleList(0 To PuzzleCount * 2 + 15)
            cur = @PuzzleList(PuzzleCount)
            cur->id = rest : cur->title = rest : cur->category = "Puzzles" : cur->level = 1
            cur->fen = "" : cur->moves = "" : cur->accept = "" : cur->hint = "" : cur->explain = ""
            PuzzleCount += 1
            loaded += 1
            Continue Do
        End If
        If cur = 0 Then
            errors &= fileName & " line " & lineNo & ": text outside a PUZZLE" & Chr(10)
            Continue Do
        End If
        Select Case kw
        Case "TITLE"    : cur->title = rest
        Case "CATEGORY" : cur->category = rest : AddCategory(rest)
        Case "LEVEL"    : cur->level = ValInt(rest)
        Case "FEN"      : cur->fen = rest
        Case "MOVES"    : cur->moves = rest
        Case "ACCEPT"   : cur->accept = rest
        Case "HINT"     : cur->hint = rest
        Case "EXPLAIN"  : cur->explain &= IIf(cur->explain = "", "", " ") & rest
        Case "END"      : cur = 0
        Case Else
            errors &= fileName & " line " & lineNo & ": unknown keyword " & kw & Chr(10)
        End Select
    Loop
    Close #f
    Return loaded
End Function

Function Puzzles_LoadFolder(ByRef folder As Const String, ByRef errors As String) As Integer
    Erase PuzzleList
    ReDim PuzzleList(0 To 63)
    PuzzleCount = 0
    CategoryCount = 0
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
        LoadPuzzleFile(folder & "/" & files(i), errors)
    Next
    If n = 0 Then errors &= "No puzzle files found in " & folder & Chr(10)
    Return PuzzleCount
End Function

Private Function WordAt(ByRef s As Const String, ByVal k As Integer) As String
    Dim As String r = Trim(s) & " "
    Dim As Integer i = 0
    Do While Len(Trim(r)) > 0
        Dim As Integer sp = InStr(r, " ")
        If i = k Then Return Left(r, sp - 1)
        r = LTrim(Mid(r, sp + 1))
        i += 1
    Loop
    Return ""
End Function

Function Puzzle_MoveCount(ByRef pz As Puzzle) As Integer
    Dim As Integer n = 0
    Do While WordAt(pz.moves, n) <> ""
        n += 1
    Loop
    Return n
End Function

Function Puzzle_Move(ByRef pz As Puzzle, ByVal k As Integer) As String
    Return WordAt(pz.moves, k)
End Function

Function Puzzle_PlayerMoves(ByRef pz As Puzzle) As Integer
    Return (Puzzle_MoveCount(pz) + 1) \ 2
End Function

Private Function StripMarks(ByRef s As Const String) As String
    Dim As String t = s
    Do While Len(t) > 0 AndAlso InStr("+#!?", Right(t, 1)) > 0
        t = Left(t, Len(t) - 1)
    Loop
    Return t
End Function

Function Puzzle_Judge(ByRef pz As Puzzle, ByVal k As Integer, ByRef p As Position, _
                      ByRef m As ChessMove) As Integer
    Dim As String san = StripMarks(Notation_MoveToSAN(p, m))
    '' Checkmate always wins the puzzle.
    Pos_MakeMove(p, m)
    Dim As Boolean mate = Pos_InCheck(p) AndAlso Not Pos_HasLegalMove(p)
    Pos_UnmakeMove(p)
    If mate Then Return PV_SOLVED
    Dim As Integer total = Puzzle_MoveCount(pz)
    If san = StripMarks(Puzzle_Move(pz, k)) Then
        If k + 1 >= total Then Return PV_SOLVED
        Return PV_CORRECT
    End If
    If k = 0 Then
        Dim As Integer i = 0
        Do
            Dim As String w = WordAt(pz.accept, i)
            If w = "" Then Exit Do
            If StripMarks(w) = san Then Return PV_SOLVED
            i += 1
        Loop
    End If
    Return PV_WRONG
End Function

Function Puzzle_Instruction(ByRef pz As Puzzle, ByVal sideToMove As Integer) As String
    Dim As String who = IIf(sideToMove = SIDE_WHITE, "White", "Black") & " to move"
    Select Case LCase(pz.category)
    Case "mate in one" : Return who & " - checkmate in one move!"
    Case "mate in two" : Return who & " - checkmate in two moves!"
    Case "mate in three" : Return who & " - checkmate in three moves!"
    End Select
    Return who & " - " & pz.title
End Function
