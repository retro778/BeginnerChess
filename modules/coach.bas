'' =====================================================================
'' BeginnerChess - coach.bas
'' See coach.bi.
'' =====================================================================
#include once "coach.bi"

Dim Shared CoKnight(0 To 7) As Integer = {33, 31, 18, 14, -33, -31, -18, -14}
Dim Shared CoKing(0 To 7) As Integer = {1, -1, 16, -16, 15, 17, -15, -17}

Function Coach_PieceValue(ByVal pieceType As Integer) As Integer
    Select Case pieceType
    Case PT_PAWN   : Return 100
    Case PT_KNIGHT : Return 300
    Case PT_BISHOP : Return 320
    Case PT_ROOK   : Return 500
    Case PT_QUEEN  : Return 900
    Case PT_KING   : Return 10000
    End Select
    Return 0
End Function

Private Function PName(ByVal pc As Integer) As String
    Return Notation_PieceName(PIECE_TYPE(pc))
End Function

'' Squares of 'side' pieces that attack sq (ignores pins; no x-rays).
'' 'removed' squares are treated as empty (pieces already used in an exchange).
Private Function AttackersOf(ByRef p As Position, ByVal sq As Integer, ByVal side As Integer, _
                             list() As Integer, removed() As Byte) As Integer
    Dim As Integer n = 0, i, t, d, k
    Dim As Integer fwd = IIf(side = SIDE_WHITE, -16, 16)       '' from sq back towards side's pawns
    For i = -1 To 1 Step 2
        t = sq + fwd + i
        If Not SQ_OFFBOARD(t) AndAlso removed(t) = 0 AndAlso p.board(t) = MAKE_PIECE(side, PT_PAWN) Then list(n) = t : n += 1
    Next
    For i = 0 To 7
        t = sq + CoKnight(i)
        If Not SQ_OFFBOARD(t) AndAlso removed(t) = 0 AndAlso p.board(t) = MAKE_PIECE(side, PT_KNIGHT) Then list(n) = t : n += 1
    Next
    Dim As Integer dirs(0 To 7) = {15, 17, -15, -17, 1, -1, 16, -16}
    For k = 0 To 7
        d = dirs(k)
        t = sq + d
        Do While Not SQ_OFFBOARD(t)
            If removed(t) = 0 AndAlso p.board(t) <> PC_EMPTY Then
                Dim As Integer pc = p.board(t)
                If PIECE_COLOR(pc) = side Then
                    Dim As Integer pt = PIECE_TYPE(pc)
                    If pt = PT_QUEEN OrElse (k < 4 AndAlso pt = PT_BISHOP) OrElse (k >= 4 AndAlso pt = PT_ROOK) Then
                        list(n) = t : n += 1
                    End If
                End If
                Exit Do
            End If
            t += d
        Loop
    Next
    For i = 0 To 7
        t = sq + CoKing(i)
        If Not SQ_OFFBOARD(t) AndAlso removed(t) = 0 AndAlso p.board(t) = MAKE_PIECE(side, PT_KING) Then list(n) = t : n += 1
    Next
    Return n
End Function

'' Exchange on 'sq': the side 'side' starts by capturing with the piece
'' on fromSq. Returns the material balance for 'side'.
Private Function Exchange(ByRef p As Position, ByVal sq As Integer, ByVal fromSq As Integer, ByVal side As Integer) As Integer
    Dim As Byte removed(0 To 127)
    Dim As Integer gain(0 To 32), depth = 0
    Dim As Integer onSq = Coach_PieceValue(PIECE_TYPE(p.board(fromSq)))
    gain(0) = Coach_PieceValue(PIECE_TYPE(p.board(sq)))
    removed(fromSq) = 1
    Dim As Integer cur = side Xor 1
    Do
        Dim As Integer list(0 To 15)
        Dim As Integer n = AttackersOf(p, sq, cur, list(), removed()), i, best = -1, bestVal = 999999
        For i = 0 To n - 1
            Dim As Integer v = Coach_PieceValue(PIECE_TYPE(p.board(list(i))))
            If v < bestVal Then bestVal = v : best = list(i)
        Next
        If best < 0 OrElse depth >= 31 Then Exit Do
        depth += 1
        gain(depth) = onSq - gain(depth - 1)
        onSq = bestVal
        removed(best) = 1
        cur Xor= 1
    Loop
    Do While depth > 0
        If -gain(depth) < gain(depth - 1) Then gain(depth - 1) = -gain(depth)
        depth -= 1
    Loop
    Return gain(0)
End Function

Function Coach_SEE(ByRef p As Position, ByRef m As ChessMove) As Integer
    If (m.flags And MF_EN_PASSANT) <> 0 Then Return 0
    If m.captured = PC_EMPTY Then Return 0
    Return Exchange(p, m.toSq, m.fromSq, PIECE_COLOR(m.piece))
End Function

Function Coach_ThreatOn(ByRef p As Position, ByVal sq As Integer) As Integer
    Dim As Integer pc = p.board(sq)
    If pc = PC_EMPTY OrElse PIECE_TYPE(pc) = PT_KING Then Return 0
    Dim As Integer enemy = PIECE_COLOR(pc) Xor 1
    Dim As Byte removed(0 To 127)
    Dim As Integer list(0 To 15)
    Dim As Integer n = AttackersOf(p, sq, enemy, list(), removed()), i, best = 0
    For i = 0 To n - 1
        Dim As Integer g = Exchange(p, sq, list(i), enemy)
        If g > best Then best = g
    Next
    Return best
End Function

Sub Coach_ThreatenedPieces(ByRef p As Position, ByVal side As Integer, result() As Integer)
    Dim As Integer s
    For s = 0 To 127
        result(s) = 0
        If SQ_OFFBOARD(s) Then Continue For
        If p.board(s) <> PC_EMPTY AndAlso PIECE_COLOR(p.board(s)) = side Then result(s) = Coach_ThreatOn(p, s)
    Next
End Sub

'' Valuable enemy pieces attacked by the piece standing on sq.
Private Function ForkTargets(ByRef p As Position, ByVal sq As Integer, ByRef names As String) As Integer
    Dim As Integer pc = p.board(sq), side = PIECE_COLOR(pc), enemy = side Xor 1
    Dim As Integer myVal = Coach_PieceValue(PIECE_TYPE(pc)), t, count = 0
    names = ""
    For t = 0 To 127
        If SQ_OFFBOARD(t) Then Continue For
        Dim As Integer tp = p.board(t)
        If tp = PC_EMPTY OrElse PIECE_COLOR(tp) <> enemy Then Continue For
        '' Is t attacked by the piece on sq?
        Dim As Byte removed(0 To 127)
        Dim As Integer list(0 To 15), n = AttackersOf(p, t, side, list(), removed()), i, hits = 0
        For i = 0 To n - 1
            If list(i) = sq Then hits = 1
        Next
        If hits = 0 Then Continue For
        Dim As Integer v = Coach_PieceValue(PIECE_TYPE(tp))
        '' Worth attacking: the king, a more valuable piece, or an unprotected one.
        If PIECE_TYPE(tp) = PT_KING OrElse v > myVal OrElse Coach_ThreatOn(p, t) > 0 Then
            count += 1
            names &= IIf(names = "", "", " and the ") & PName(tp)
        End If
    Next
    Return count
End Function

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

'' Total value of the side's threatened pieces.
Private Function ThreatSum(ByRef p As Position, ByVal side As Integer, ByRef worstSq As Integer) As Integer
    Dim As Integer s, total = 0, worst = 0
    worstSq = NO_SQUARE
    For s = 0 To 127
        If SQ_OFFBOARD(s) Then Continue For
        If p.board(s) <> PC_EMPTY AndAlso PIECE_COLOR(p.board(s)) = side Then
            Dim As Integer t = Coach_ThreatOn(p, s)
            total += t
            If t > worst Then worst = t : worstSq = s
        End If
    Next
    Return total
End Function

Private Function IsPassedPawn(ByRef p As Position, ByVal sq As Integer) As Boolean
    Dim As Integer side = PIECE_COLOR(p.board(sq)), f = SQ_FILE(sq), r = SQ_RANK(sq), ff, rr
    Dim As Integer enemyPawn = MAKE_PIECE(side Xor 1, PT_PAWN)
    For ff = f - 1 To f + 1
        If ff < 0 OrElse ff > 7 Then Continue For
        If side = SIDE_WHITE Then
            For rr = r + 1 To 6
                If p.board(MAKE_SQ(ff, rr)) = enemyPawn Then Return False
            Next
        Else
            For rr = 1 To r - 1
                If p.board(MAKE_SQ(ff, rr)) = enemyPawn Then Return False
            Next
        End If
    Next
    Return True
End Function

Private Function NonPawnMaterial(ByRef p As Position) As Integer
    Dim As Integer s, total = 0
    For s = 0 To 127
        If SQ_OFFBOARD(s) Then Continue For
        Dim As Integer pt = PIECE_TYPE(p.board(s))
        If pt >= PT_KNIGHT AndAlso pt <= PT_QUEEN Then total += Coach_PieceValue(pt)
    Next
    Return total
End Function

Function Coach_ExplainMove(ByRef p As Position, ByRef m As ChessMove) As String
    Dim As Integer side = p.sideToMove, enemy = side Xor 1
    Dim As Integer pt = PIECE_TYPE(m.piece)
    Dim As String pieceName = Notation_PieceName(pt)
    Dim As String fromName = Sq_Name(m.fromSq), toName = Sq_Name(m.toSq)

    '' Facts before the move
    Dim As Integer threatBefore = Coach_ThreatOn(p, m.fromSq)
    Dim As Integer worstBefore
    Dim As Integer ourThreatsBefore = ThreatSum(p, side, worstBefore)
    Dim As Integer see = Coach_SEE(p, m)
    Dim As Boolean defendedTarget = False
    If m.captured <> PC_EMPTY AndAlso (m.flags And MF_EN_PASSANT) = 0 Then
        Dim As Byte removed(0 To 127)
        Dim As Integer list(0 To 15)
        defendedTarget = (AttackersOf(p, m.toSq, enemy, list(), removed()) > 0)
    End If
    '' Did the opponent threaten mate? (pretend it is their move)
    Dim As Boolean mateThreat = False
    If Not Pos_InCheck(p) Then
        Pos_MakeNullMove(p)
        mateThreat = HasMateInOne(p)
        Pos_UnmakeMove(p)
    End If

    Pos_MakeMove(p, m)
    Dim As Boolean givesCheck = Pos_InCheck(p)
    Dim As Boolean mate = givesCheck AndAlso Not Pos_HasLegalMove(p)
    Dim As String forkNames
    Dim As Integer forks = ForkTargets(p, m.toSq, forkNames)
    Dim As Integer threatAfter = Coach_ThreatOn(p, m.toSq)
    Dim As Integer worstAfter
    Dim As Integer ourThreatsAfter = ThreatSum(p, side, worstAfter)
    Dim As Boolean stillMateThreat = False
    If mateThreat AndAlso Not givesCheck Then stillMateThreat = HasMateInOne(p)
    Dim As Boolean passed = (pt = PT_PAWN) AndAlso IsPassedPawn(p, m.toSq)
    Dim As Integer npm = NonPawnMaterial(p)
    Pos_UnmakeMove(p)

    If mate Then Return "This is checkmate!"
    If givesCheck AndAlso forks >= 2 Then
        Return "Check! Your " & pieceName & " attacks the " & forkNames & " at the same time - a fork!"
    End If
    If m.captured <> PC_EMPTY AndAlso see >= 0 Then
        Dim As String victim = PName(m.captured)
        If (m.flags And MF_EN_PASSANT) <> 0 Then Return "Capture the pawn en passant!"
        If Not defendedTarget Then Return "Take the " & victim & " on " & toName & " - it is not protected!"
        If see > 0 AndAlso Coach_PieceValue(PIECE_TYPE(m.captured)) > Coach_PieceValue(pt) Then
            Return "Capture the " & victim & ": it is worth more than your " & pieceName & "."
        End If
        If see > 0 Then Return "Capture on " & toName & " and win material."
        If mateThreat AndAlso Not stillMateThreat Then Return "Capture on " & toName & ": this also stops the checkmate threat."
        Return "Trade pieces on " & toName & "."
    End If
    If m.promotion <> PT_NONE Then Return "Promote your pawn to a " & Notation_PieceName(m.promotion) & "!"
    If mateThreat AndAlso Not stillMateThreat Then Return "Your opponent threatens checkmate. This move stops it!"
    If threatBefore > 0 AndAlso threatAfter = 0 AndAlso m.fromSq <> m.toSq Then
        Return "Your " & pieceName & " on " & fromName & " is under attack. Moving it to " & toName & " saves it."
    End If
    If forks >= 2 Then Return "Fork! Your " & pieceName & " attacks the " & forkNames & " at the same time."
    If ourThreatsBefore > 0 AndAlso ourThreatsAfter < ourThreatsBefore AndAlso worstBefore <> NO_SQUARE Then
        Return "This protects your " & PName(p.board(worstBefore)) & " on " & Sq_Name(worstBefore) & "."
    End If
    If (m.flags And MF_CASTLE) <> 0 Then Return "Castle: your king gets safe and your rook joins the game."
    If givesCheck Then Return "Give check - it keeps the enemy king busy."
    If passed AndAlso npm <= 1300 Then Return "Push your passed pawn - it wants to become a queen!"
    If p.fullmoveNumber <= 12 AndAlso npm > 1300 Then
        If (pt = PT_KNIGHT OrElse pt = PT_BISHOP) AndAlso SQ_RANK(m.fromSq) = IIf(side = SIDE_WHITE, 0, 7) Then
            Return "Develop your " & pieceName & " towards the centre."
        End If
        If pt = PT_PAWN AndAlso (SQ_FILE(m.toSq) = 3 OrElse SQ_FILE(m.toSq) = 4) Then
            Return "Take space in the centre with your pawn."
        End If
    End If
    If pt = PT_ROOK Then
        Dim As Integer f = SQ_FILE(m.toSq), r, pawns = 0
        For r = 0 To 7
            If PIECE_TYPE(p.board(MAKE_SQ(f, r))) = PT_PAWN Then pawns += 1
        Next
        If pawns = 0 Then Return "Put your rook on the open " & Chr(Asc("a") + f) & "-file."
    End If
    If passed Then Return "Push your passed pawn - it wants to become a queen!"
    If pt = PT_KING AndAlso npm <= 1300 Then Return "Bring your king into the game - in the endgame the king is a strong piece."
    Return "This move improves the position of your " & pieceName & "."
End Function

Function Coach_ExplainThreat(ByRef p As Position, ByRef r As ChessMove) As String
    Dim As String san = Notation_MoveToSAN(p, r)
    Dim As Integer see = Coach_SEE(p, r)
    Pos_MakeMove(p, r)
    Dim As Boolean check = Pos_InCheck(p)
    Dim As Boolean mate = check AndAlso Not Pos_HasLegalMove(p)
    Dim As String forkNames
    Dim As Integer forks = ForkTargets(p, r.toSq, forkNames)
    Pos_UnmakeMove(p)
    If mate Then Return "Now your opponent can checkmate you with " & san & "!"
    If r.captured <> PC_EMPTY AndAlso see > 0 Then
        Return "Now your opponent can win your " & PName(r.captured) & " with " & san & "."
    End If
    If forks >= 2 Then Return "Now " & san & " would attack your " & forkNames & " at the same time (a fork)."
    If r.promotion <> PT_NONE Then Return "Now your opponent can make a new queen with " & san & "."
    Return "Your opponent now has a strong move: " & san & "."
End Function

Function Coach_EvalText(ByVal whiteScore As Integer) As String
    If whiteScore > SCORE_MATE - 200 Then Return "White can force checkmate in " & ((SCORE_MATE - whiteScore + 1) \ 2) & " moves!"
    If whiteScore < -SCORE_MATE + 200 Then Return "Black can force checkmate in " & ((SCORE_MATE + whiteScore + 1) \ 2) & " moves!"
    Dim As Integer a = Abs(whiteScore)
    Dim As String who = IIf(whiteScore > 0, "White", "Black")
    If a < 35 Then Return "The position is about equal."
    If a < 110 Then Return who & " is slightly better."
    If a < 350 Then Return who & " is better (about " & IIf(a < 160, "one pawn", (a + 50) \ 100 & " pawns") & ")."
    If a < 900 Then Return who & " is clearly winning."
    Return who & " is winning easily."
End Function
