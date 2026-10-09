'' =====================================================================
'' BeginnerChess - notation.bas
'' SAN / UCI move notation. See notation.bi.
'' =====================================================================
#include once "notation.bi"

Private Function PieceLetter(ByVal pt As Integer) As String
    Select Case pt
    Case PT_KNIGHT : Return "N"
    Case PT_BISHOP : Return "B"
    Case PT_ROOK   : Return "R"
    Case PT_QUEEN  : Return "Q"
    Case PT_KING   : Return "K"
    End Select
    Return ""
End Function

Function Notation_PieceName(ByVal pieceType As Integer) As String
    Select Case pieceType
    Case PT_PAWN   : Return "pawn"
    Case PT_KNIGHT : Return "knight"
    Case PT_BISHOP : Return "bishop"
    Case PT_ROOK   : Return "rook"
    Case PT_QUEEN  : Return "queen"
    Case PT_KING   : Return "king"
    End Select
    Return "piece"
End Function

Function Notation_MoveToUCI(ByRef m As ChessMove) As String
    Dim As String s = Sq_Name(m.fromSq) & Sq_Name(m.toSq)
    If m.promotion <> PT_NONE Then s &= LCase(PieceLetter(m.promotion))
    Return s
End Function

Function Notation_MoveToSAN(ByRef p As Position, ByRef m As ChessMove) As String
    Dim As String san
    Dim As Integer pt = PIECE_TYPE(m.piece)

    If m.flags And MF_CASTLE Then
        san = IIf(m.toSq > m.fromSq, "O-O", "O-O-O")
    ElseIf pt = PT_PAWN Then
        If m.flags And MF_CAPTURE Then san = Left(Sq_Name(m.fromSq), 1) & "x"
        san &= Sq_Name(m.toSq)
        If m.promotion <> PT_NONE Then san &= "=" & PieceLetter(m.promotion)
    Else
        san = PieceLetter(pt)
        '' Disambiguation: other pieces of the same kind that can also
        '' legally reach the destination square.
        Dim As MoveList list
        Pos_GenerateLegal(p, list)
        Dim As Boolean ambiguous = False, sameFile = False, sameRank = False
        Dim As Integer i
        For i = 0 To list.count - 1
            With list.moves(i)
                If .piece = m.piece AndAlso .toSq = m.toSq AndAlso .fromSq <> m.fromSq Then
                    ambiguous = True
                    If SQ_FILE(.fromSq) = SQ_FILE(m.fromSq) Then sameFile = True
                    If SQ_RANK(.fromSq) = SQ_RANK(m.fromSq) Then sameRank = True
                End If
            End With
        Next
        If ambiguous Then
            If Not sameFile Then
                san &= Left(Sq_Name(m.fromSq), 1)
            ElseIf Not sameRank Then
                san &= Right(Sq_Name(m.fromSq), 1)
            Else
                san &= Sq_Name(m.fromSq)
            End If
        End If
        If m.flags And MF_CAPTURE Then san &= "x"
        san &= Sq_Name(m.toSq)
    End If

    '' Check / checkmate suffix
    If Pos_MakeMove(p, m) Then
        If Pos_InCheck(p) Then
            san &= IIf(Pos_HasLegalMove(p), "+", "#")
        End If
        Pos_UnmakeMove(p)
    End If
    Return san
End Function

Function Notation_ParseUCI(ByRef p As Position, ByRef text As Const String, _
                           ByRef outMove As ChessMove, ByRef errMsg As String) As Boolean
    Dim As String s = LCase(Trim(text))
    errMsg = ""
    If Len(s) < 4 OrElse Len(s) > 5 Then
        errMsg = "Coordinate moves look like e2e4 or e7e8q."
        Return False
    End If
    Dim As Integer fromSq = Sq_Parse(Mid(s, 1, 2))
    Dim As Integer toSq = Sq_Parse(Mid(s, 3, 2))
    If fromSq = NO_SQUARE OrElse toSq = NO_SQUARE Then
        errMsg = "'" & text & "' does not name two squares."
        Return False
    End If
    Dim As Integer promo = PT_NONE
    If Len(s) = 5 Then
        Select Case Mid(s, 5, 1)
        Case "q" : promo = PT_QUEEN
        Case "r" : promo = PT_ROOK
        Case "b" : promo = PT_BISHOP
        Case "n" : promo = PT_KNIGHT
        Case Else
            errMsg = "A pawn can only promote to q, r, b or n."
            Return False
        End Select
    End If
    If Pos_FindLegalMove(p, fromSq, toSq, promo, outMove) Then Return True

    '' Explain why the move is not allowed.
    Dim As Integer pc = p.board(fromSq)
    If pc = PC_EMPTY Then
        errMsg = "There is no piece on " & Sq_Name(fromSq) & "."
    ElseIf PIECE_COLOR(pc) <> p.sideToMove Then
        errMsg = "The piece on " & Sq_Name(fromSq) & " belongs to your opponent."
    ElseIf promo = PT_NONE AndAlso Pos_FindLegalMove(p, fromSq, toSq, PT_QUEEN, outMove) Then
        errMsg = "Please choose a promotion piece, e.g. " & s & "q."
    Else
        errMsg = "The " & Notation_PieceName(PIECE_TYPE(pc)) & " on " & Sq_Name(fromSq) & _
                 " cannot move to " & Sq_Name(toSq) & "."
    End If
    Return False
End Function

Function Notation_ParseSAN(ByRef p As Position, ByRef text As Const String, _
                           ByRef outMove As ChessMove, ByRef errMsg As String) As Boolean
    errMsg = ""
    Dim As String s = Trim(text)

    '' Strip check/mate marks and annotation symbols at the end.
    Do While Len(s) > 0 AndAlso InStr("+#!?", Right(s, 1)) > 0
        s = Left(s, Len(s) - 1)
    Loop
    If LCase(Right(s, 4)) = "e.p." Then s = RTrim(Left(s, Len(s) - 4))
    If Len(s) = 0 Then
        errMsg = "Please type a move."
        Return False
    End If

    Dim As MoveList list
    Pos_GenerateLegal(p, list)
    Dim As Integer i

    '' --- Castling ---
    '' Accept both letter O and digit zero.
    Dim As String up = ""
    For i = 1 To Len(s)
        Dim As String c = UCase(Mid(s, i, 1))
        If c = "0" Then c = "O"
        up &= c
    Next
    If up = "O-O" OrElse up = "OO" OrElse up = "O-O-O" OrElse up = "OOO" Then
        Dim As Boolean longSide = (up = "O-O-O" OrElse up = "OOO")
        For i = 0 To list.count - 1
            With list.moves(i)
                If .flags And MF_CASTLE Then
                    If (longSide AndAlso .toSq < .fromSq) OrElse (Not longSide AndAlso .toSq > .fromSq) Then
                        outMove = list.moves(i)
                        Return True
                    End If
                End If
            End With
        Next
        errMsg = "Castling " & IIf(longSide, "queenside", "kingside") & " is not allowed right now."
        Return False
    End If

    '' --- Promotion piece ---
    Dim As Integer promo = PT_NONE
    Dim As Integer eqPos = InStr(s, "=")
    Dim As String promoChar = ""
    If eqPos > 0 Then
        promoChar = Mid(s, eqPos + 1, 1)
        s = Left(s, eqPos - 1)
    ElseIf Len(s) >= 3 AndAlso InStr("12345678", Mid(s, Len(s) - 1, 1)) > 0 AndAlso _
           InStr("QRBNqrbn", Right(s, 1)) > 0 Then
        promoChar = Right(s, 1)
        s = Left(s, Len(s) - 1)
    ElseIf Len(s) >= 4 AndAlso Right(s, 1) = ")" Then
        '' e.g. "e8(Q)"
        promoChar = Mid(s, Len(s) - 1, 1)
        s = Left(s, Len(s) - 3)
    End If
    If promoChar <> "" Then
        Select Case UCase(promoChar)
        Case "Q" : promo = PT_QUEEN
        Case "R" : promo = PT_ROOK
        Case "B" : promo = PT_BISHOP
        Case "N" : promo = PT_KNIGHT
        Case Else
            errMsg = "A pawn can only promote to a queen, rook, bishop or knight."
            Return False
        End Select
    End If

    '' --- Moving piece ---
    Dim As Integer pt = PT_PAWN
    Dim As String first = Left(s, 1)
    Select Case first
    Case "K", "k" : pt = PT_KING
    Case "Q", "q" : pt = PT_QUEEN
    Case "R", "r" : pt = PT_ROOK
    Case "N", "n" : pt = PT_KNIGHT
    Case "B"      : pt = PT_BISHOP     '' lowercase b is the b-file
    End Select
    If pt <> PT_PAWN Then s = Mid(s, 2)

    '' Remove capture / separator characters.
    Dim As String body = ""
    For i = 1 To Len(s)
        Dim As String c = Mid(s, i, 1)
        If c <> "x" AndAlso c <> "X" AndAlso c <> ":" AndAlso c <> "-" Then body &= LCase(c)
    Next

    '' Destination square = the last two characters.
    If Len(body) < 2 OrElse Len(body) > 4 Then
        errMsg = "'" & text & "' is not a move I understand. Try something like e4, Nf3 or O-O."
        Return False
    End If
    Dim As Integer toSq = Sq_Parse(Right(body, 2))
    If toSq = NO_SQUARE Then
        errMsg = "'" & text & "' does not end with a square such as e4."
        Return False
    End If

    '' Optional disambiguation hints before the destination.
    Dim As String hint = Left(body, Len(body) - 2)
    Dim As Integer hintFile = -1, hintRank = -1
    For i = 1 To Len(hint)
        Dim As String c = Mid(hint, i, 1)
        If c >= "a" AndAlso c <= "h" Then
            hintFile = Asc(c) - Asc("a")
        ElseIf c >= "1" AndAlso c <= "8" Then
            hintRank = Asc(c) - Asc("1")
        Else
            errMsg = "'" & text & "' is not a move I understand."
            Return False
        End If
    Next

    '' --- Find matching legal moves ---
    Dim As Integer matches = 0, needsPromo = 0
    Dim As String candidates = ""
    For i = 0 To list.count - 1
        With list.moves(i)
            If PIECE_TYPE(.piece) <> pt Then Continue For
            If .toSq <> toSq Then Continue For
            If (.flags And MF_CASTLE) <> 0 Then Continue For
            If hintFile >= 0 AndAlso SQ_FILE(.fromSq) <> hintFile Then Continue For
            If hintRank >= 0 AndAlso SQ_RANK(.fromSq) <> hintRank Then Continue For
            If .promotion <> promo Then
                If promo = PT_NONE Then needsPromo = 1
                Continue For
            End If
            outMove = list.moves(i)
            matches += 1
            If candidates <> "" Then candidates &= " or "
            candidates &= Sq_Name(.fromSq)
        End With
    Next

    If matches = 1 Then Return True
    If matches > 1 Then
        errMsg = "More than one " & Notation_PieceName(pt) & " can go to " & Sq_Name(toSq) & _
                 " (from " & candidates & "). Say which one, e.g. " & PieceLetter(pt) & _
                 Left(candidates, 1) & Sq_Name(toSq) & "."
        Return False
    End If
    If needsPromo Then
        errMsg = "Please choose a promotion piece, e.g. " & Sq_Name(toSq) & "=Q."
        Return False
    End If
    If promo <> PT_NONE AndAlso pt <> PT_PAWN Then
        errMsg = "Only pawns can promote."
        Return False
    End If
    errMsg = "No " & Notation_PieceName(pt) & " can legally move to " & Sq_Name(toSq) & " right now."
    Return False
End Function

Function Notation_ParseMove(ByRef p As Position, ByRef text As Const String, _
                            ByRef outMove As ChessMove, ByRef errMsg As String) As Boolean
    Dim As String s = LCase(Trim(text))
    '' Coordinate form: two squares, optional promotion letter.
    If (Len(s) = 4 OrElse Len(s) = 5) AndAlso Sq_Parse(Mid(s, 1, 2)) <> NO_SQUARE _
       AndAlso Sq_Parse(Mid(s, 3, 2)) <> NO_SQUARE Then
        Return Notation_ParseUCI(p, s, outMove, errMsg)
    End If
    Return Notation_ParseSAN(p, text, outMove, errMsg)
End Function
