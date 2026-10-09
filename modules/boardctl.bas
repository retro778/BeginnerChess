'' =====================================================================
'' BeginnerChess - boardctl.bas
'' See boardctl.bi.
'' =====================================================================
#include once "boardctl.bi"

Sub BC_Reset(ByRef bc As BoardControl)
    bc.selected = NO_SQUARE
    bc.dragArmed = False
    bc.dragging = False
    bc.deselectOnUp = False
    bc.promoActive = False
    bc.errorSq = NO_SQUARE
    bc.animActive = False
    bc.pendingSound = -1
    bc.legalPly = -1
    bc.lastFrom = NO_SQUARE
    bc.lastTo = NO_SQUARE
End Sub

Function BC_Busy(ByRef bc As BoardControl) As Boolean
    Return bc.animActive OrElse bc.promoActive
End Function

Private Sub Finish(ByRef bc As BoardControl)
    bc.animActive = False
    If bc.pendingSound >= 0 Then Audio_Play(bc.pendingSound)
    bc.pendingSound = -1
End Sub

Sub BC_AnimateMove(ByRef bc As BoardControl, ByRef p As Position, ByRef m As ChessMove)
    Finish(bc)
    bc.lastFrom = m.fromSq
    bc.lastTo = m.toSq
    '' Sound for the move (position is after the move).
    Dim As Integer snd = SND_MOVE
    If p.kingSq(p.sideToMove) <> NO_SQUARE Then
        If Pos_InCheck(p) Then
            snd = IIf(Pos_HasLegalMove(p), SND_CHECK, SND_CHECKMATE)
        ElseIf m.promotion <> PT_NONE Then
            snd = SND_PROMOTE
        ElseIf (m.flags And MF_CASTLE) <> 0 Then
            snd = SND_CASTLE
        ElseIf (m.flags And MF_CAPTURE) <> 0 Then
            snd = SND_CAPTURE
        End If
    End If
    If AppConfig.animationMs <= 0 Then
        Audio_Play(snd)
        Exit Sub
    End If
    bc.animActive = True
    bc.animStart = Timer
    bc.animDur = AppConfig.animationMs / 1000.0
    bc.animFrom = m.fromSq
    bc.animTo = m.toSq
    bc.animPc = p.board(m.toSq)
    bc.anim2From = NO_SQUARE
    bc.anim2To = NO_SQUARE
    If m.flags And MF_CASTLE Then
        If m.toSq > m.fromSq Then
            bc.anim2From = m.toSq + 1 : bc.anim2To = m.toSq - 1
        Else
            bc.anim2From = m.toSq - 2 : bc.anim2To = m.toSq + 1
        End If
        bc.anim2Pc = p.board(bc.anim2To)
    End If
    bc.pendingSound = snd
End Sub

'' Promotion chooser drawn over the board. Returns the chosen piece type
'' (PT_NONE while still choosing, -1 when cancelled).
Private Function PromotionChooser(ByRef bc As BoardControl, ByRef bv As BoardView, ByVal side As Integer) As Integer
    Dim As Integer sq = bv.sqSize
    Dim As Integer bw = sq * 4 + 5 * 14, bh = sq + 100
    Dim As Integer x = bv.x + sq * 4 - bw \ 2, y = bv.y + sq * 4 - bh \ 2
    Gfx_FillRect(bv.x, bv.y, sq * 8, sq * 8, RGBA(0, 0, 0, 90))
    Gfx_Panel(x, y, bw, bh, 14, RGB(252, 248, 238), RGB(110, 84, 50))
    Text_DrawCentered(x + bw \ 2, y + 14, "Promote your pawn! Choose a piece:", 20, RGB(60, 40, 20))
    Dim As Integer types(0 To 3) = {PT_QUEEN, PT_ROOK, PT_BISHOP, PT_KNIGHT}, i
    For i = 0 To 3
        Dim As Integer px = x + 14 + i * (sq + 14), py = y + 46
        Dim As Boolean hov = UI_Hover(px, py, sq, sq)
        Gfx_Panel(px, py, sq, sq, 10, IIf(hov, RGB(255, 236, 170), RGB(236, 226, 206)), RGB(150, 120, 80), False)
        Board_DrawPiece(bv, MAKE_PIECE(side, types(i)), px, py)
        Text_DrawCentered(px + sq \ 2, py + sq + 6, Notation_PieceName(types(i)), 16, RGB(80, 60, 40))
        If hov AndAlso UI.pressed Then
            UI.pressed = False
            Return types(i)
        End If
    Next
    If UI.keyCode = KEY_ESCAPE Then
        UI.keyCode = 0
        Return -1
    End If
    Return PT_NONE
End Function

Private Function TargetKind(ByRef bc As BoardControl, ByVal fromSq As Integer, ByVal toSq As Integer) As Integer
    Dim As Integer i
    For i = 0 To bc.legal.count - 1
        If bc.legal.moves(i).fromSq = fromSq AndAlso bc.legal.moves(i).toSq = toSq Then
            Return IIf((bc.legal.moves(i).flags And MF_CAPTURE) <> 0, 2, 1)
        End If
    Next
    Return 0
End Function

'' Tries from->to. Returns 1 = move ready in outMove, 0 = illegal, 2 = promotion chooser opened.
Private Function TryMove(ByRef bc As BoardControl, ByRef p As Position, ByVal fromSq As Integer, ByVal toSq As Integer, _
                         ByRef outMove As ChessMove, ByRef illegalText As String) As Integer
    Dim As Integer i, count = 0, found = -1
    For i = 0 To bc.legal.count - 1
        If bc.legal.moves(i).fromSq = fromSq AndAlso bc.legal.moves(i).toSq = toSq Then
            count += 1
            found = i
        End If
    Next
    If count = 0 Then
        illegalText = Explain_IllegalMove(p, fromSq, toSq)
        bc.errorSq = toSq
        bc.errorTime = Timer
        bc.selected = NO_SQUARE
        Audio_Play(SND_ILLEGAL)
        Return 0
    End If
    If count > 1 Then
        bc.promoActive = True
        bc.promoFrom = fromSq
        bc.promoTo = toSq
        Return 2
    End If
    outMove = bc.legal.moves(found)
    bc.selected = NO_SQUARE
    Return 1
End Function

Function BC_Frame(ByRef bc As BoardControl, ByRef bv As BoardView, ByRef p As Position, _
                  ByVal allowInput As Boolean, ByRef extra As BoardMarks, _
                  ByRef outMove As ChessMove, ByRef illegalText As String) As Boolean
    illegalText = ""
    Dim As Boolean moved = False
    Dim As Boolean playable = (p.kingSq(0) <> NO_SQUARE) AndAlso (p.kingSq(1) <> NO_SQUARE)
    If playable AndAlso (CBool(bc.legalKey <> p.hash) OrElse CBool(bc.legalPly <> p.historyCount)) Then
        Pos_GenerateLegal(p, bc.legal)
        bc.legalKey = p.hash
        bc.legalPly = p.historyCount
    End If
    If Not playable Then bc.legal.count = 0

    '' --- Marks ---
    Dim As BoardMarks mk = extra
    If bc.lastFrom <> NO_SQUARE Then mk.lastFrom = bc.lastFrom : mk.lastTo = bc.lastTo
    If playable Then
        If Pos_InCheck(p) Then mk.checkSq = p.kingSq(p.sideToMove)
    End If
    mk.selectedSq = bc.selected
    Dim As Integer i
    If bc.selected <> NO_SQUARE AndAlso AppConfig.showLegalMoves Then
        For i = 0 To bc.legal.count - 1
            If bc.legal.moves(i).fromSq = bc.selected Then
                mk.targets(bc.legal.moves(i).toSq) = IIf((bc.legal.moves(i).flags And MF_CAPTURE) <> 0, 2, 1)
            End If
        Next
        Dim As Integer hov = Board_SquareAt(bv, UI.mx, UI.my)
        If hov <> NO_SQUARE AndAlso Not UI.blockInput Then
            If mk.targets(hov) <> 0 Then mk.hoverSq = hov
        End If
    End If
    If bc.errorSq <> NO_SQUARE Then
        Dim As Double age = Timer - bc.errorTime
        If age < 0.6 Then
            mk.errorSq = bc.errorSq
            mk.errorAlpha = 150 * (1 - age / 0.6)
        Else
            bc.errorSq = NO_SQUARE
        End If
    End If
    If bc.dragging Then mk.hideSq = bc.dragSq
    Dim As Single animT = 1
    If bc.animActive Then
        UI_KeepFast()
        animT = (Timer - bc.animStart) / bc.animDur
        If animT >= 1 Then
            Finish(bc)
        Else
            mk.hideSq = bc.animTo
            mk.hideSq2 = bc.anim2To
        End If
    End If
    Board_Draw(bv, p, mk)

    Dim As Integer sq = bv.sqSize
    If bc.animActive Then
        Dim As Single e = 1 - (1 - animT) * (1 - animT)
        Dim As Integer x0, y0, x1, y1
        Board_SquareXY(bv, bc.animFrom, x0, y0)
        Board_SquareXY(bv, bc.animTo, x1, y1)
        Board_DrawPiece(bv, bc.animPc, x0 + (x1 - x0) * e, y0 + (y1 - y0) * e)
        If bc.anim2From <> NO_SQUARE Then
            Board_SquareXY(bv, bc.anim2From, x0, y0)
            Board_SquareXY(bv, bc.anim2To, x1, y1)
            Board_DrawPiece(bv, bc.anim2Pc, x0 + (x1 - x0) * e, y0 + (y1 - y0) * e)
        End If
    End If
    If bc.dragging Then Board_DrawPiece(bv, p.board(bc.dragSq), UI.mx - sq \ 2, UI.my - sq \ 2)

    '' --- Promotion chooser ---
    If bc.promoActive Then
        Dim As Integer choice = PromotionChooser(bc, bv, p.sideToMove)
        If choice = -1 Then
            bc.promoActive = False
            bc.selected = NO_SQUARE
        ElseIf choice <> PT_NONE Then
            bc.promoActive = False
            If Pos_FindLegalMove(p, bc.promoFrom, bc.promoTo, choice, outMove) Then
                bc.selected = NO_SQUARE
                Return True
            End If
        End If
        Return False
    End If

    '' --- Mouse ---
    If Not allowInput OrElse Not playable OrElse UI.blockInput Then
        bc.dragArmed = False
        bc.dragging = False
        Return False
    End If
    Dim As Integer sqUnder = Board_SquareAt(bv, UI.mx, UI.my)
    If UI.pressed AndAlso sqUnder <> NO_SQUARE Then
        If bc.animActive Then Finish(bc)
        bc.deselectOnUp = False
        Dim As Integer pc = p.board(sqUnder)
        Dim As Boolean own = (pc <> PC_EMPTY) AndAlso (PIECE_COLOR(pc) = p.sideToMove)
        If bc.selected <> NO_SQUARE AndAlso sqUnder <> bc.selected AndAlso TargetKind(bc, bc.selected, sqUnder) > 0 Then
            If TryMove(bc, p, bc.selected, sqUnder, outMove, illegalText) = 1 Then moved = True
        ElseIf own Then
            If bc.selected = sqUnder Then bc.deselectOnUp = True
            bc.selected = sqUnder
            bc.dragArmed = True
            bc.dragSq = sqUnder
            bc.pressX = UI.mx
            bc.pressY = UI.my
        ElseIf bc.selected <> NO_SQUARE Then
            TryMove(bc, p, bc.selected, sqUnder, outMove, illegalText)
        ElseIf pc <> PC_EMPTY Then
            illegalText = "That is " & IIf(PIECE_COLOR(pc) = SIDE_WHITE, "White", "Black") & "'s piece. It is " & _
                          IIf(p.sideToMove = SIDE_WHITE, "White", "Black") & "'s turn to move."
        End If
    End If
    If bc.dragArmed AndAlso UI.down AndAlso Not bc.dragging Then
        If Abs(UI.mx - bc.pressX) + Abs(UI.my - bc.pressY) > 6 Then bc.dragging = True
    End If
    If UI.released Then
        If bc.dragging Then
            If sqUnder <> NO_SQUARE AndAlso sqUnder <> bc.dragSq Then
                If TryMove(bc, p, bc.dragSq, sqUnder, outMove, illegalText) = 1 Then moved = True
            End If
        ElseIf bc.deselectOnUp Then
            bc.selected = NO_SQUARE
        End If
        bc.dragging = False
        bc.dragArmed = False
        bc.deselectOnUp = False
    End If
    Return moved
End Function
