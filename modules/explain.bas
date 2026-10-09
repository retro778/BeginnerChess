'' =====================================================================
'' BeginnerChess - explain.bas
'' See explain.bi.
'' =====================================================================
#include once "explain.bi"

Function Explain_HowPieceMoves(ByVal pieceType As Integer) As String
    Select Case pieceType
    Case PT_PAWN
        Return "Pawns move straight forward one square (two on their first move) and capture one square diagonally forward."
    Case PT_KNIGHT
        Return "Knights move in an L-shape: two squares in one direction, then one square to the side. They can jump over pieces."
    Case PT_BISHOP
        Return "Bishops move diagonally, as far as they like, but cannot jump over pieces."
    Case PT_ROOK
        Return "Rooks move in straight lines along ranks and files, as far as they like, but cannot jump over pieces."
    Case PT_QUEEN
        Return "The queen moves in straight lines or diagonally, as far as she likes, but cannot jump over pieces."
    Case PT_KING
        Return "The king moves one square in any direction."
    End Select
    Return ""
End Function

'' True if any piece stands strictly between a and b on a straight line or diagonal.
Private Function PathBlocked(ByRef p As Position, ByVal a As Integer, ByVal b As Integer) As Boolean
    Dim As Integer df = SQ_FILE(b) - SQ_FILE(a), dr = SQ_RANK(b) - SQ_RANK(a)
    Dim As Integer stepF = Sgn(df), stepR = Sgn(dr)
    Dim As Integer s = a + stepR * 16 + stepF
    Do While s <> b
        If SQ_OFFBOARD(s) Then Return False
        If p.board(s) <> PC_EMPTY Then Return True
        s += stepR * 16 + stepF
    Loop
    Return False
End Function

Private Function ExplainCastling(ByRef p As Position, ByVal fromSq As Integer, ByVal toSq As Integer) As String
    Dim As Integer us = p.sideToMove, them = us Xor 1
    Dim As Boolean kingSide = toSq > fromSq
    Dim As Integer rights
    If us = SIDE_WHITE Then
        rights = IIf(kingSide, CR_WHITE_KING, CR_WHITE_QUEEN)
    Else
        rights = IIf(kingSide, CR_BLACK_KING, CR_BLACK_QUEEN)
    End If
    Dim As String sideName = IIf(kingSide, "kingside", "queenside")
    If (p.castling And rights) = 0 Then
        Return "You can't castle " & sideName & " any more: the king or that rook has already moved (or the rook was captured)."
    End If
    Dim As Integer rookSq = IIf(kingSide, fromSq + 3, fromSq - 4)
    If PathBlocked(p, fromSq, rookSq) Then
        Return "You can't castle yet: all the squares between the king and the rook must be empty."
    End If
    If Pos_IsSquareAttacked(p, fromSq, them) Then
        Return "You can't castle while your king is in check."
    End If
    Dim As Integer passSq = IIf(kingSide, fromSq + 1, fromSq - 1)
    If Pos_IsSquareAttacked(p, passSq, them) Then
        Return "You can't castle through " & Sq_Name(passSq) & ": an enemy piece attacks that square."
    End If
    Return "You can't castle into check: an enemy piece attacks " & Sq_Name(toSq) & "."
End Function

Function Explain_IllegalMove(ByRef p As Position, ByVal fromSq As Integer, _
                             ByVal toSq As Integer) As String
    If fromSq = NO_SQUARE OrElse toSq = NO_SQUARE Then Return ""
    Dim As Integer pc = p.board(fromSq)
    If pc = PC_EMPTY Then Return "There is no piece on " & Sq_Name(fromSq) & "."
    Dim As Integer us = p.sideToMove
    If PIECE_COLOR(pc) <> us Then
        Return "That piece belongs to your opponent. It is " & IIf(us = SIDE_WHITE, "White", "Black") & "'s turn."
    End If

    '' Legal after all? (Any promotion piece counts.)
    Dim As MoveList legal
    Pos_GenerateLegal(p, legal)
    Dim As Integer i
    For i = 0 To legal.count - 1
        If legal.moves(i).fromSq = fromSq AndAlso legal.moves(i).toSq = toSq Then Return ""
    Next

    Dim As Integer pt = PIECE_TYPE(pc)
    Dim As String pieceName = Notation_PieceName(pt)
    If fromSq = toSq Then Return ""

    Dim As Integer target = p.board(toSq)
    If target <> PC_EMPTY AndAlso PIECE_COLOR(target) = us Then
        Return "You can't capture your own piece!"
    End If

    '' Castling attempt: king moves two files along its home rank.
    If pt = PT_KING AndAlso SQ_RANK(fromSq) = SQ_RANK(toSq) AndAlso Abs(SQ_FILE(toSq) - SQ_FILE(fromSq)) = 2 _
       AndAlso SQ_FILE(fromSq) = 4 AndAlso SQ_RANK(fromSq) = IIf(us = SIDE_WHITE, 0, 7) Then
        Return ExplainCastling(p, fromSq, toSq)
    End If

    '' Is it a move the piece could make if its king were safe?
    Dim As MoveList pseudo
    Pos_GeneratePseudo(p, pseudo)
    Dim As Boolean geometric = False
    For i = 0 To pseudo.count - 1
        If pseudo.moves(i).fromSq = fromSq AndAlso pseudo.moves(i).toSq = toSq Then geometric = True
    Next
    If geometric Then
        If pt = PT_KING Then
            Return "Your king can't go to " & Sq_Name(toSq) & ": it would be in check there."
        ElseIf Pos_InCheck(p) Then
            Return "You are in check! This move does not save your king. Move the king, block the check, or capture the attacker."
        Else
            Return "Your " & pieceName & " is pinned: it is shielding your king from an attack, so it can't move there."
        End If
    End If

    '' The piece simply doesn't move that way.
    Dim As Integer df = SQ_FILE(toSq) - SQ_FILE(fromSq), dr = SQ_RANK(toSq) - SQ_RANK(fromSq)
    Dim As Integer fwd = IIf(us = SIDE_WHITE, 1, -1)
    Select Case pt
    Case PT_PAWN
        If dr * fwd <= 0 Then Return "Pawns can only move forward, never backward or sideways."
        If Abs(df) = 1 AndAlso dr = fwd Then
            Return "Pawns capture diagonally, but there is nothing to capture on " & Sq_Name(toSq) & "."
        End If
        If df = 0 AndAlso target <> PC_EMPTY Then
            Return "A pawn can't capture straight ahead: the square in front of it is blocked."
        End If
        If df = 0 AndAlso dr = 2 * fwd Then
            If SQ_RANK(fromSq) <> IIf(us = SIDE_WHITE, 1, 6) Then
                Return "A pawn may move two squares only on its very first move."
            End If
            Return "The pawn can't jump over the piece in front of it."
        End If
        Return Explain_HowPieceMoves(PT_PAWN)
    Case PT_BISHOP, PT_ROOK, PT_QUEEN
        Dim As Boolean straight = (df = 0 OrElse dr = 0)
        Dim As Boolean diagonal = (Abs(df) = Abs(dr))
        Dim As Boolean shapeOk = (pt = PT_BISHOP AndAlso diagonal) OrElse (pt = PT_ROOK AndAlso straight) _
                                 OrElse (pt = PT_QUEEN AndAlso (straight OrElse diagonal))
        If shapeOk AndAlso PathBlocked(p, fromSq, toSq) Then
            Return "Another piece is in the way. The " & pieceName & " can't jump over pieces."
        End If
        Return Explain_HowPieceMoves(pt)
    Case Else
        Return Explain_HowPieceMoves(pt)
    End Select
End Function
