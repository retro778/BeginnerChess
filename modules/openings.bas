'' =====================================================================
'' BeginnerChess - openings.bas
'' See openings.bi.
'' =====================================================================
#include once "openings.bi"

Type BookMove
    hash   As ULongInt
    fromSq As UByte
    toSq   As UByte
    promo  As UByte
    weight As Integer
End Type

Type BookName
    hash As ULongInt
    eco  As String
    name As String
End Type

'' Names of the lines passing through each position; a position that only
'' one named line passes through is labelled with that name.
Type PassName
    hash  As ULongInt
    name  As String
    eco   As String
    multi As Boolean
End Type
Dim Shared PassNames() As PassName
Dim Shared PassCount As Integer = 0

Dim Shared BookMoves() As BookMove
Dim Shared BookMoveCount As Integer = 0
Dim Shared BookNames() As BookName
Dim Shared BookNameCount As Integer = 0

Private Sub AddPassName(ByVal hash As ULongInt, ByRef eco As Const String, ByRef nm As Const String)
    Dim As Integer i
    For i = 0 To PassCount - 1
        If PassNames(i).hash = hash Then
            If PassNames(i).name <> nm Then PassNames(i).multi = True
            Exit Sub
        End If
    Next
    If PassCount > UBound(PassNames) Then ReDim Preserve PassNames(0 To PassCount * 2 + 63)
    PassNames(PassCount).hash = hash
    PassNames(PassCount).name = nm
    PassNames(PassCount).eco = eco
    PassNames(PassCount).multi = False
    PassCount += 1
End Sub

Sub Book_Clear()
    Erase BookMoves
    Erase BookNames
    Erase PassNames
    PassCount = 0
    BookMoveCount = 0
    BookNameCount = 0
End Sub

Function Book_IsLoaded() As Boolean
    Return BookMoveCount > 0
End Function

Private Sub AddBookMove(ByVal hash As ULongInt, ByRef m As ChessMove)
    Dim As Integer i
    For i = 0 To BookMoveCount - 1
        With BookMoves(i)
            If .hash = hash AndAlso .fromSq = m.fromSq AndAlso .toSq = m.toSq AndAlso .promo = m.promotion Then
                .weight += 1
                Exit Sub
            End If
        End With
    Next
    If BookMoveCount > UBound(BookMoves) Then ReDim Preserve BookMoves(0 To BookMoveCount * 2 + 63)
    With BookMoves(BookMoveCount)
        .hash = hash
        .fromSq = m.fromSq
        .toSq = m.toSq
        .promo = m.promotion
        .weight = 1
    End With
    BookMoveCount += 1
End Sub

Private Sub AddBookName(ByVal hash As ULongInt, ByRef eco As Const String, ByRef nm As Const String)
    Dim As Integer i
    For i = 0 To BookNameCount - 1
        If BookNames(i).hash = hash Then Exit Sub        '' first line wins
    Next
    If BookNameCount > UBound(BookNames) Then ReDim Preserve BookNames(0 To BookNameCount * 2 + 31)
    BookNames(BookNameCount).hash = hash
    BookNames(BookNameCount).eco = eco
    BookNames(BookNameCount).name = nm
    BookNameCount += 1
End Sub

Function Book_Load(ByRef fileName As Const String, ByRef badLines As Integer, _
                   ByRef firstError As String) As Integer
    badLines = 0
    firstError = ""
    Book_Clear()
    ReDim BookMoves(0 To 255)
    ReDim BookNames(0 To 63)
    ReDim PassNames(0 To 255)
    Dim As Integer f = FreeFile
    If Open(fileName For Input As #f) <> 0 Then
        firstError = "Opening book not found: " & fileName
        Return 0
    End If
    Static p As Position
    Dim As Integer loaded = 0, lineNo = 0
    Dim As String ln
    Do While Not EOF(f)
        Line Input #f, ln
        lineNo += 1
        ln = Trim(ln, Any " " & Chr(9, 13))
        If ln = "" OrElse Left(ln, 1) = "#" Then Continue Do
        Dim As Integer bar1 = InStr(ln, "|"), bar2 = InStr(bar1 + 1, ln, "|")
        If bar1 = 0 OrElse bar2 = 0 Then
            badLines += 1
            If firstError = "" Then firstError = "Line " & lineNo & ": expected 'ECO | name | moves'."
            Continue Do
        End If
        Dim As String eco = Trim(Left(ln, bar1 - 1))
        Dim As String nm = Trim(Mid(ln, bar1 + 1, bar2 - bar1 - 1))
        Dim As String moves = Trim(Mid(ln, bar2 + 1)) & " "
        Pos_SetStart(p)
        Dim As Boolean ok = True
        Do While Len(Trim(moves)) > 0
            Dim As Integer sp = InStr(moves, " ")
            Dim As String san = Left(moves, sp - 1)
            moves = LTrim(Mid(moves, sp + 1))
            Dim As ChessMove m
            Dim As String errMsg
            If Not Notation_ParseSAN(p, san, m, errMsg) Then
                badLines += 1
                If firstError = "" Then firstError = "Line " & lineNo & " (" & nm & "): move '" & san & "': " & errMsg
                ok = False
                Exit Do
            End If
            AddBookMove(p.hash, m)
            Pos_MakeMove(p, m)
            AddPassName(p.hash, eco, nm)
        Loop
        If ok Then
            AddBookName(p.hash, eco, nm)
            loaded += 1
        End If
    Loop
    Close #f
    Return loaded
End Function

Function Book_MoveCount(ByRef p As Position) As Integer
    Dim As Integer i, n = 0
    For i = 0 To BookMoveCount - 1
        If BookMoves(i).hash = p.hash Then n += 1
    Next
    Return n
End Function

Function Book_Probe(ByRef p As Position, ByVal r As Double, ByRef m As ChessMove) As Boolean
    Dim As Integer i, total = 0
    For i = 0 To BookMoveCount - 1
        If BookMoves(i).hash = p.hash Then total += BookMoves(i).weight
    Next
    If total = 0 Then Return False
    Dim As Integer pick = Int(r * total)
    For i = 0 To BookMoveCount - 1
        If BookMoves(i).hash = p.hash Then
            pick -= BookMoves(i).weight
            If pick < 0 Then
                '' Only trust the book move if it is legal here (hash safety).
                Return Pos_FindLegalMove(p, BookMoves(i).fromSq, BookMoves(i).toSq, BookMoves(i).promo, m)
            End If
        End If
    Next
    Return False
End Function

'' Finds the name for the latest named position of the game.
Private Function FindName(ByRef p As Position, ByRef eco As String) As String
    Dim As Integer i, k
    Dim As ULongInt h = p.hash
    For k = p.historyCount To 0 Step -1
        If k < p.historyCount Then h = p.undoStack(k).hash
        '' A line ends here: its name is the most specific.
        For i = 0 To BookNameCount - 1
            If BookNames(i).hash = h Then
                eco = BookNames(i).eco
                Return BookNames(i).name
            End If
        Next
        '' Only one named line passes through here.
        For i = 0 To PassCount - 1
            If PassNames(i).hash = h AndAlso Not PassNames(i).multi Then
                eco = PassNames(i).eco
                Return PassNames(i).name
            End If
        Next
    Next
    eco = ""
    Return ""
End Function

Function Book_OpeningName(ByRef p As Position) As String
    Dim As String eco
    Return FindName(p, eco)
End Function

Function Book_OpeningEco(ByRef p As Position) As String
    Dim As String eco
    FindName(p, eco)
    Return eco
End Function
