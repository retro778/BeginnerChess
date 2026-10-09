'' =====================================================================
'' BeginnerChess - game.bas
'' Game record and end-of-game rules. See game.bi.
''
'' Draw policy follows the FIDE Laws of Chess:
''   automatic: checkmate, stalemate, insufficient material (dead position),
''              fivefold repetition, 75-move rule
''   claimed:   threefold repetition, fifty-move rule (by the player to move,
''              also for the position their intended move would create)
'' Checkmate always takes priority over the move-count rules.
'' =====================================================================
#include once "game.bi"

Function Side_Name(ByVal side As Integer) As String
    Return IIf(side = SIDE_WHITE, "White", "Black")
End Function

Private Sub ResetRecord(ByRef g As ChessGame)
    Dim As Integer i
    For i = 0 To g.moveCount - 1
        g.sanMoves(i) = ""
        g.comments(i) = ""
    Next
    g.moveCount = 0
    g.result = RESULT_ONGOING
    g.termination = TERM_NONE
End Sub

Sub Game_New(ByRef g As ChessGame)
    ResetRecord(g)
    Pos_SetStart(g.pos)
    g.startFEN = START_FEN
End Sub

Function Game_NewFromFEN(ByRef g As ChessGame, ByRef fen As Const String, _
                         ByRef errMsg As String) As Boolean
    If Not Pos_LoadFEN(g.pos, fen, errMsg) Then Return False
    ResetRecord(g)
    g.startFEN = Pos_GetFEN(g.pos)
    Game_UpdateStatus(g)     '' the position might already be mate/stalemate
    Return True
End Function

Sub Game_UpdateStatus(ByRef g As ChessGame)
    g.result = RESULT_ONGOING
    g.termination = TERM_NONE

    If Not Pos_HasLegalMove(g.pos) Then
        If Pos_InCheck(g.pos) Then
            g.termination = TERM_CHECKMATE
            g.result = IIf(g.pos.sideToMove = SIDE_WHITE, RESULT_BLACK_WINS, RESULT_WHITE_WINS)
        Else
            g.termination = TERM_STALEMATE
            g.result = RESULT_DRAW
        End If
    ElseIf Pos_IsInsufficientMaterial(g.pos) Then
        g.termination = TERM_INSUFFICIENT
        g.result = RESULT_DRAW
    ElseIf Pos_RepetitionCount(g.pos) >= 5 Then
        g.termination = TERM_FIVEFOLD
        g.result = RESULT_DRAW
    ElseIf g.pos.halfmoveClock >= 150 Then
        g.termination = TERM_SEVENTY_FIVE_MOVE
        g.result = RESULT_DRAW
    End If
End Sub

Function Game_ClaimableDraw(ByRef g As ChessGame) As GameTermination
    If Game_IsOver(g) Then Return TERM_NONE
    If Pos_RepetitionCount(g.pos) >= 3 Then Return TERM_THREEFOLD
    If g.pos.halfmoveClock >= 100 Then Return TERM_FIFTY_MOVE
    Return TERM_NONE
End Function

Function Game_ClaimDraw(ByRef g As ChessGame) As Boolean
    Dim As GameTermination t = Game_ClaimableDraw(g)
    If t = TERM_NONE Then Return False
    g.termination = t
    g.result = RESULT_DRAW
    Return True
End Function

Function Game_ClaimableDrawWithMove(ByRef g As ChessGame, ByRef m As ChessMove) As GameTermination
    If Game_IsOver(g) Then Return TERM_NONE
    Dim As ChessMove legal
    If Not Pos_FindLegalMove(g.pos, m.fromSq, m.toSq, m.promotion, legal) Then Return TERM_NONE
    Dim As GameTermination t = TERM_NONE
    Pos_MakeMove(g.pos, legal)
    '' A move that checkmates wins; there is nothing to claim.
    If Not (Pos_InCheck(g.pos) AndAlso Not Pos_HasLegalMove(g.pos)) Then
        If Pos_RepetitionCount(g.pos) >= 3 Then
            t = TERM_THREEFOLD
        ElseIf g.pos.halfmoveClock >= 100 Then
            t = TERM_FIFTY_MOVE
        End If
    End If
    Pos_UnmakeMove(g.pos)
    Return t
End Function

Function Game_ClaimDrawWithMove(ByRef g As ChessGame, ByRef m As ChessMove, _
                                ByRef errMsg As String) As Boolean
    Dim As GameTermination t = Game_ClaimableDrawWithMove(g, m)
    If t = TERM_NONE Then
        errMsg = "That move does not allow a draw claim."
        Return False
    End If
    If Not Game_PlayMove(g, m, errMsg) Then Return False
    '' Playing the move may itself have ended the game (e.g. stalemate).
    If Not Game_IsOver(g) Then
        g.termination = t
        g.result = RESULT_DRAW
    End If
    Return True
End Function

Function Game_ClaimHint(ByRef g As ChessGame) As String
    Select Case Game_ClaimableDraw(g)
    Case TERM_THREEFOLD
        Return Side_Name(g.pos.sideToMove) & " may claim a draw: this position has appeared three times."
    Case TERM_FIFTY_MOVE
        Return Side_Name(g.pos.sideToMove) & " may claim a draw: 50 moves without a capture or pawn move."
    End Select
    Return ""
End Function

Function Game_IsOver(ByRef g As ChessGame) As Boolean
    Return g.result <> RESULT_ONGOING
End Function

Function Game_PlayMove(ByRef g As ChessGame, ByRef m As ChessMove, _
                       ByRef errMsg As String) As Boolean
    errMsg = ""
    If Game_IsOver(g) Then
        errMsg = "The game is over."
        Return False
    End If
    If g.moveCount >= MAX_HISTORY - 256 Then
        errMsg = "This game is too long to continue."
        Return False
    End If
    Dim As ChessMove legal
    If Not Pos_FindLegalMove(g.pos, m.fromSq, m.toSq, m.promotion, legal) Then
        errMsg = "That move is not legal."
        Return False
    End If
    g.sanMoves(g.moveCount) = Notation_MoveToSAN(g.pos, legal)
    g.comments(g.moveCount) = ""
    Pos_MakeMove(g.pos, legal)
    g.moveCount += 1
    Game_UpdateStatus(g)
    Return True
End Function

Function Game_PlayMoveText(ByRef g As ChessGame, ByRef text As Const String, _
                           ByRef errMsg As String) As Boolean
    If Game_IsOver(g) Then
        errMsg = "The game is over."
        Return False
    End If
    Dim As ChessMove m
    If Not Notation_ParseMove(g.pos, text, m, errMsg) Then Return False
    Return Game_PlayMove(g, m, errMsg)
End Function

Function Game_Undo(ByRef g As ChessGame) As Boolean
    '' A resignation, agreement or draw claim is undone first, without
    '' taking back a move.
    Select Case g.termination
    Case TERM_RESIGNATION, TERM_AGREEMENT, TERM_THREEFOLD, TERM_FIFTY_MOVE
        Game_UpdateStatus(g)
        Return True
    End Select
    If g.moveCount <= 0 Then Return False
    Pos_UnmakeMove(g.pos)
    g.moveCount -= 1
    g.sanMoves(g.moveCount) = ""
    g.comments(g.moveCount) = ""
    Game_UpdateStatus(g)
    Return True
End Function

Sub Game_Resign(ByRef g As ChessGame, ByVal side As Integer)
    If Game_IsOver(g) Then Exit Sub
    g.termination = TERM_RESIGNATION
    g.result = IIf(side = SIDE_WHITE, RESULT_BLACK_WINS, RESULT_WHITE_WINS)
End Sub

Sub Game_AgreeDraw(ByRef g As ChessGame)
    If Game_IsOver(g) Then Exit Sub
    g.termination = TERM_AGREEMENT
    g.result = RESULT_DRAW
End Sub

Function Game_ApplyResult(ByRef g As ChessGame, ByRef result As Const String) As Boolean
    Select Case Trim(result)
    Case "*"
        Return True
    Case "1-0", "0-1"
        If Game_IsOver(g) Then Return True
        '' The game record ends without mate: the loser resigned (or lost
        '' on time - PGN does not say, unless a Termination tag is used).
        g.termination = TERM_RESIGNATION
        g.result = IIf(Trim(result) = "1-0", RESULT_WHITE_WINS, RESULT_BLACK_WINS)
        Return True
    Case "1/2-1/2"
        If Game_IsOver(g) Then Return True
        If Not Game_ClaimDraw(g) Then Game_AgreeDraw(g)
        Return True
    End Select
    Return False
End Function

Function Game_LastMove(ByRef g As ChessGame) As ChessMove
    Dim As ChessMove none
    If g.pos.historyCount <= 0 Then Return none
    Return g.pos.undoStack(g.pos.historyCount - 1).mv
End Function

Function Game_ResultString(ByRef g As ChessGame) As String
    Select Case g.result
    Case RESULT_WHITE_WINS : Return "1-0"
    Case RESULT_BLACK_WINS : Return "0-1"
    Case RESULT_DRAW       : Return "1/2-1/2"
    End Select
    Return "*"
End Function

Function Game_StatusText(ByRef g As ChessGame) As String
    Dim As String winner
    If g.result = RESULT_WHITE_WINS Then winner = "White" Else winner = "Black"
    Select Case g.termination
    Case TERM_CHECKMATE   : Return "Checkmate! " & winner & " wins."
    Case TERM_STALEMATE   : Return "Stalemate! " & Side_Name(g.pos.sideToMove) & _
                                   " has no legal move but is not in check. It's a draw."
    Case TERM_THREEFOLD   : Return "Draw claimed: the same position appeared three times."
    Case TERM_FIFTY_MOVE  : Return "Draw claimed: fifty moves without a capture or pawn move."
    Case TERM_FIVEFOLD    : Return "Draw: the same position appeared five times."
    Case TERM_SEVENTY_FIVE_MOVE : Return "Draw: 75 moves without a capture or pawn move."
    Case TERM_INSUFFICIENT: Return "Draw: neither side has enough pieces to checkmate."
    Case TERM_AGREEMENT   : Return "Draw agreed."
    Case TERM_RESIGNATION : Return IIf(g.result = RESULT_WHITE_WINS, "Black", "White") & _
                                   " resigned. " & winner & " wins."
    End Select
    Dim As String s = Side_Name(g.pos.sideToMove) & " to move."
    If Pos_InCheck(g.pos) Then
        If Pos_CountCheckers(g.pos) >= 2 Then
            s = "Double check! " & s
        Else
            s = "Check! " & s
        End If
    End If
    Return s
End Function

Function Game_MoveListText(ByRef g As ChessGame) As String
    '' Work out the move number and side of the first recorded move.
    Dim As Integer moveNo = g.pos.fullmoveNumber, side = g.pos.sideToMove
    Dim As Integer i
    For i = 1 To g.moveCount
        side Xor= 1
        If side = SIDE_BLACK Then moveNo -= 1
    Next
    Dim As String s = ""
    For i = 0 To g.moveCount - 1
        If side = SIDE_WHITE Then
            s &= moveNo & ". "
        ElseIf i = 0 Then
            s &= moveNo & "... "
        End If
        s &= g.sanMoves(i) & " "
        If side = SIDE_BLACK Then moveNo += 1
        side Xor= 1
    Next
    Return RTrim(s)
End Function
