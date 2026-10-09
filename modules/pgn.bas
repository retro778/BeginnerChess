'' =====================================================================
'' BeginnerChess - pgn.bas
'' See pgn.bi.
'' =====================================================================
#include once "pgn.bi"

'' ---------------------------------------------------------------------
'' Tags
'' ---------------------------------------------------------------------
Sub Pgn_ClearTags(ByRef t As PgnTags)
    Dim As Integer i
    For i = 0 To PGN_MAX_TAGS - 1
        t.names(i) = ""
        t.values(i) = ""
    Next
    t.count = 0
End Sub

Sub Pgn_SetTag(ByRef t As PgnTags, ByRef tagName As Const String, ByRef value As Const String)
    Dim As Integer i
    For i = 0 To t.count - 1
        If t.names(i) = tagName Then
            t.values(i) = value
            Exit Sub
        End If
    Next
    If t.count >= PGN_MAX_TAGS Then Exit Sub
    t.names(t.count) = tagName
    t.values(t.count) = value
    t.count += 1
End Sub

Function Pgn_GetTag(ByRef t As PgnTags, ByRef tagName As Const String, _
                    ByRef defaultValue As Const String = "") As String
    Dim As Integer i
    For i = 0 To t.count - 1
        If t.names(i) = tagName Then Return t.values(i)
    Next
    Return defaultValue
End Function

Function Pgn_Today() As String
    Dim As String d = Date()                  '' mm-dd-yyyy
    Return Mid(d, 7, 4) & "." & Left(d, 2) & "." & Mid(d, 4, 2)
End Function

'' ---------------------------------------------------------------------
'' Export
'' ---------------------------------------------------------------------
Private Function EscapeTag(ByRef v As Const String) As String
    Dim As String r = ""
    Dim As Integer i
    For i = 1 To Len(v)
        Dim As String c = Mid(v, i, 1)
        If c = """" OrElse c = "\" Then r &= "\"
        If Asc(c) >= 32 Then r &= c
    Next
    Return r
End Function

Private Function CleanComment(ByRef v As Const String) As String
    Dim As String r = ""
    Dim As Integer i
    For i = 1 To Len(v)
        Dim As String c = Mid(v, i, 1)
        If c = "}" Then c = ")"
        If c = "{" Then c = "("
        If Asc(c) < 32 Then c = " "
        r &= c
    Next
    Return Trim(r)
End Function

Function Pgn_Export(ByRef g As ChessGame, ByRef tags As PgnTags) As String
    Dim As String nl = Chr(10)
    Dim As String pgnText = ""
    Dim As String roster(0 To 6) = {"Event", "Site", "Date", "Round", "White", "Black", "Result"}
    Dim As Integer i
    For i = 0 To 6
        Dim As String v
        If roster(i) = "Result" Then
            v = Game_ResultString(g)
        Else
            v = Pgn_GetTag(tags, roster(i), "?")
            If v = "" Then v = "?"
        End If
        pgnText &= "[" & roster(i) & " """ & EscapeTag(v) & """]" & nl
    Next
    Dim As Boolean fromFEN = (g.startFEN <> START_FEN)
    If fromFEN Then
        pgnText &= "[SetUp ""1""]" & nl
        pgnText &= "[FEN """ & g.startFEN & """]" & nl
    End If
    For i = 0 To tags.count - 1
        Select Case tags.names(i)
        Case "Event", "Site", "Date", "Round", "White", "Black", "Result", "SetUp", "FEN", "PlyCount"
        Case Else
            pgnText &= "[" & tags.names(i) & " """ & EscapeTag(tags.values(i)) & """]" & nl
        End Select
    Next
    pgnText &= "[PlyCount """ & g.moveCount & """]" & nl & nl

    '' Movetext, wrapped below 80 columns.
    '' Work pgnText the number and side of the first move.
    Dim As Integer side = g.pos.sideToMove, moveNo = g.pos.fullmoveNumber
    For i = 1 To g.moveCount
        side Xor= 1
        If side = SIDE_BLACK Then moveNo -= 1
    Next
    Dim As String lineBuf = "", tok
    Dim As Boolean needNumber = True
    #macro EMIT(t)
        If Len(lineBuf) > 0 AndAlso Len(lineBuf) + 1 + Len(t) > 79 Then
            pgnText &= lineBuf & nl
            lineBuf = ""
        End If
        lineBuf &= IIf(Len(lineBuf) > 0, " ", "") & t
    #endmacro
    For i = 0 To g.moveCount - 1
        If side = SIDE_WHITE Then
            tok = moveNo & "."
            EMIT(tok)
        ElseIf needNumber Then
            tok = moveNo & "..."
            EMIT(tok)
        End If
        needNumber = False
        EMIT(g.sanMoves(i))
        If g.comments(i) <> "" Then
            '' Long comments are emitted word by word so wrapping still works.
            Dim As String cm = "{" & CleanComment(g.comments(i)) & "}", w = ""
            Dim As Integer k
            For k = 1 To Len(cm) + 1
                Dim As String c = IIf(k <= Len(cm), Mid(cm, k, 1), " ")
                If c = " " Then
                    If w <> "" Then
                        EMIT(w)
                    End If
                    w = ""
                Else
                    w &= c
                End If
            Next
            needNumber = True                 '' black's move after a comment gets "N..."
        End If
        If side = SIDE_BLACK Then moveNo += 1
        side Xor= 1
    Next
    tok = Game_ResultString(g)
    EMIT(tok)
    #undef EMIT
    pgnText &= lineBuf & nl
    Return pgnText
End Function

'' ---------------------------------------------------------------------
'' Import
'' ---------------------------------------------------------------------
Function Pgn_SplitGames(ByRef text As Const String, games() As String) As Integer
    Dim As Integer n = 0, i = 1, L = Len(text)
    Dim As String cur = ""
    Dim As Boolean inMoves = False
    Do While i <= L
        '' Read one line.
        Dim As Integer e = InStr(i, text, Chr(10))
        If e = 0 Then e = L + 1
        Dim As String ln = Mid(text, i, e - i)
        i = e + 1
        If Right(ln, 1) = Chr(13) Then ln = Left(ln, Len(ln) - 1)
        Dim As String t = Trim(ln)
        If Left(t, 1) = "[" AndAlso inMoves Then
            '' A tag after movetext starts a new game.
            If Len(Trim(cur)) > 0 Then
                If n > UBound(games) Then ReDim Preserve games(0 To n * 2 + 15)
                games(n) = cur
                n += 1
            End If
            cur = ""
            inMoves = False
        End If
        If t <> "" AndAlso Left(t, 1) <> "[" AndAlso Left(t, 1) <> "%" Then inMoves = True
        cur &= ln & Chr(10)
    Loop
    If Len(Trim(cur, Any " " & Chr(9, 10, 13))) > 0 Then
        If n > UBound(games) Then ReDim Preserve games(0 To n + 1)
        games(n) = cur
        n += 1
    End If
    Return n
End Function

'' Parses "[Name "value"]" lines into tags; returns the movetext.
Private Function SplitTagsAndMoves(ByRef gameText As Const String, ByRef tags As PgnTags) As String
    Pgn_ClearTags(tags)
    Dim As String moves = ""
    Dim As Integer i = 1, L = Len(gameText)
    Do While i <= L
        Dim As Integer e = InStr(i, gameText, Chr(10))
        If e = 0 Then e = L + 1
        Dim As String ln = Mid(gameText, i, e - i)
        i = e + 1
        Dim As String t = Trim(ln, Any " " & Chr(9, 13))
        If Left(t, 1) = "%" Then Continue Do                 '' escape line
        If Left(t, 1) = "[" AndAlso Right(t, 1) = "]" Then
            Dim As Integer q1 = InStr(t, """")
            If q1 > 0 Then
                Dim As String tagName = Trim(Mid(t, 2, q1 - 2))
                '' Value up to the last quote, with \" and \\ unescaped.
                Dim As String raw = Mid(t, q1 + 1, Len(t) - q1 - 1)
                If Right(raw, 1) = """" Then raw = Left(raw, Len(raw) - 1)
                Dim As String v = ""
                Dim As Integer k = 1
                Do While k <= Len(raw)
                    Dim As String c = Mid(raw, k, 1)
                    If c = "\" AndAlso k < Len(raw) Then
                        k += 1
                        c = Mid(raw, k, 1)
                    End If
                    v &= c
                    k += 1
                Loop
                Pgn_SetTag(tags, tagName, v)
            End If
        Else
            moves &= t & Chr(10)
        End If
    Loop
    Return moves
End Function

Sub Pgn_ParseTags(ByRef gameText As Const String, ByRef tags As PgnTags)
    SplitTagsAndMoves(gameText, tags)
End Sub

Function Pgn_ParseGame(ByRef gameText As Const String, ByRef g As ChessGame, _
                       ByRef tags As PgnTags, ByRef errMsg As String) As Boolean
    errMsg = ""
    Dim As String moves = SplitTagsAndMoves(gameText, tags)

    '' Starting position
    Dim As String fen = Pgn_GetTag(tags, "FEN")
    If fen <> "" Then
        Dim As String fenErr
        If Not Game_NewFromFEN(g, fen, fenErr) Then
            errMsg = "The game's FEN tag is not valid: " & fenErr
            Return False
        End If
    Else
        Game_New(g)
    End If

    Dim As Integer i = 1, L = Len(moves)
    Dim As String resultToken = ""
    Do While i <= L
        Dim As String c = Mid(moves, i, 1)
        Select Case c
        Case " ", Chr(9), Chr(13), Chr(10)
            i += 1
        Case "{"
            Dim As Integer e = InStr(i + 1, moves, "}")
            If e = 0 Then e = L + 1
            Dim As String cm = Trim(Mid(moves, i + 1, e - i - 1))
            '' Comments may span several lines: turn line breaks into single spaces.
            Dim As String clean = ""
            Dim As Integer q
            For q = 1 To Len(cm)
                Dim As String ch1 = Mid(cm, q, 1)
                If ch1 = Chr(10) OrElse ch1 = Chr(13) OrElse ch1 = Chr(9) Then ch1 = " "
                If ch1 <> " " OrElse Right(clean, 1) <> " " Then clean &= ch1
            Next
            cm = Trim(clean)
            If g.moveCount > 0 Then
                If g.comments(g.moveCount - 1) <> "" Then g.comments(g.moveCount - 1) &= " "
                g.comments(g.moveCount - 1) &= cm
            End If
            i = e + 1
        Case ";"
            '' Comment to the end of the line.
            Dim As Integer e = InStr(i, moves, Chr(10))
            If e = 0 Then e = L + 1
            i = e + 1
        Case "("
            '' Skip a (possibly nested) variation, including comments in it.
            Dim As Integer depth = 0
            Do While i <= L
                Dim As String d = Mid(moves, i, 1)
                If d = "{" Then
                    Dim As Integer e = InStr(i + 1, moves, "}")
                    i = IIf(e = 0, L + 1, e + 1)
                    Continue Do
                End If
                If d = "(" Then depth += 1
                If d = ")" Then
                    depth -= 1
                    If depth = 0 Then i += 1 : Exit Do
                End If
                i += 1
            Loop
        Case ")"
            i += 1
        Case Else
            '' A token up to the next separator.
            Dim As Integer j = i
            Do While j <= L AndAlso InStr(" {}();" & Chr(9, 10, 13), Mid(moves, j, 1)) = 0
                j += 1
            Loop
            Dim As String tok = Mid(moves, i, j - i)
            i = j
            If Left(tok, 1) = "$" Then Continue Do               '' NAG
            If tok = "1-0" OrElse tok = "0-1" OrElse tok = "1/2-1/2" OrElse tok = "*" Then
                resultToken = tok
                Exit Do
            End If
            '' Strip a move number ("12." / "12..." / "12.e4").
            Dim As Integer k = 1
            Do While k <= Len(tok) AndAlso Mid(tok, k, 1) >= "0" AndAlso Mid(tok, k, 1) <= "9"
                k += 1
            Loop
            If k > 1 AndAlso k <= Len(tok) AndAlso Mid(tok, k, 1) = "." Then
                Do While k <= Len(tok) AndAlso Mid(tok, k, 1) = "."
                    k += 1
                Loop
                tok = Mid(tok, k)
            ElseIf k > Len(tok) Then
                Continue Do                                       '' bare number
            End If
            If tok = "" OrElse tok = "e.p." OrElse tok = "+" OrElse tok = "#" Then Continue Do
            If Left(tok, 1) = "!" OrElse Left(tok, 1) = "?" Then Continue Do
            '' Some files write castling as 0-0; avoid confusing it with results.
            Dim As ChessMove m
            Dim As String why
            If Not Notation_ParseSAN(g.pos, tok, m, why) Then
                Dim As Integer moveNo = g.pos.fullmoveNumber
                errMsg = "Move " & moveNo & IIf(g.pos.sideToMove = SIDE_WHITE, ". ", "... ") & tok & _
                         " is not possible: " & why
                Return False
            End If
            If Not Game_PlayMove(g, m, why) Then
                errMsg = "Move " & tok & " could not be played: " & why
                Return False
            End If
        End Select
    Loop

    If resultToken = "" Then resultToken = Pgn_GetTag(tags, "Result", "*")
    Game_ApplyResult(g, resultToken)
    Return True
End Function

'' ---------------------------------------------------------------------
'' Files
'' ---------------------------------------------------------------------
Function Pgn_ReadFile(ByRef fileName As Const String, ByRef text As String) As Boolean
    text = ""
    Dim As Integer f = FreeFile
    If Open(fileName For Binary Access Read As #f) <> 0 Then Return False
    Dim As LongInt size = LOF(f)
    If size > 0 Then
        text = Space(size)
        Get #f, , text
    End If
    Close #f
    '' Skip a UTF-8 byte order mark.
    If Left(text, 3) = Chr(239, 187, 191) Then text = Mid(text, 4)
    Return True
End Function

Function Pgn_WriteFile(ByRef fileName As Const String, ByRef text As Const String, _
                       ByVal appendMode As Boolean = False) As Boolean
    Dim As Integer f = FreeFile
    Dim As Integer rc
    If appendMode Then
        rc = Open(fileName For Append As #f)
    Else
        rc = Open(fileName For Output As #f)
    End If
    If rc <> 0 Then Return False
    Print #f, text;
    Close #f
    Return True
End Function
