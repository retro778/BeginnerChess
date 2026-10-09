'' =====================================================================
'' BeginnerChess - analyzeui.bas
'' Analyze Position: set up any position (board editor, FEN), explore
'' moves on the board, and let the engine explain the position: an
'' evaluation bar, the evaluation in words, the best move with an arrow
'' and an explanation, the main line, and threatened pieces.
'' =====================================================================
#include once "screens.bi"
#include once "boardctl.bi"
#include once "coach.bi"

Type AnalyzeState
    pos          As Position
    baseHistory  As Integer          '' moves before this are not undone here
    returnTo     As Integer
    flipped      As Boolean
    thinking     As Boolean
    resultValid  As Boolean
    result       As EngineResult
    resultKey    As ULongInt
    resultPly    As Integer
    showThreats  As Boolean
    editing      As Boolean
    palette      As Integer          '' piece code to place (0 = eraser)
    editSide     As Integer
    message      As String
    explainKey   As ULongInt
    explainText  As String
    pvText       As String
    beforeEdit   As String           '' FEN to restore when editing is cancelled
End Type
Dim Shared AZ As AnalyzeState
Dim Shared AZBoard As BoardView
Dim Shared AZBC As BoardControl
Dim Shared AZInput As InputDialogState
Dim Shared AZPieces As PieceImages

Private Sub ResetEngine()
    Engine_StopAsync()
    AZ.thinking = False
    AZ.resultValid = False
End Sub

Sub Analyze_Start(ByRef fen As Const String, ByVal returnScreen As Integer)
    Dim As String e
    If Not Pos_LoadFEN(AZ.pos, fen, e) Then Pos_SetStart(AZ.pos)
    AZ.baseHistory = 0
    AZ.returnTo = returnScreen
    AZ.flipped = (AZ.pos.sideToMove = SIDE_BLACK)
    AZ.showThreats = False
    AZ.editing = False
    AZ.palette = PC_WQ
    AZ.message = ""
    BC_Reset(AZBC)
    ResetEngine()
End Sub

'' Builds a FEN from the editor board; castling rights are given when
'' king and rook stand on their starting squares.
Private Function EditorFEN() As String
    Dim As String fen = Pos_GetFEN(AZ.pos)
    Dim As String placement = Left(fen, InStr(fen, " ") - 1)
    Dim As String cr = ""
    If AZ.pos.board(SQ_E1) = PC_WK AndAlso AZ.pos.board(SQ_H1) = PC_WR Then cr &= "K"
    If AZ.pos.board(SQ_E1) = PC_WK AndAlso AZ.pos.board(SQ_A1) = PC_WR Then cr &= "Q"
    If AZ.pos.board(SQ_E8) = PC_BK AndAlso AZ.pos.board(SQ_H8) = PC_BR Then cr &= "k"
    If AZ.pos.board(SQ_E8) = PC_BK AndAlso AZ.pos.board(SQ_A8) = PC_BR Then cr &= "q"
    If cr = "" Then cr = "-"
    Return placement & IIf(AZ.editSide = SIDE_WHITE, " w ", " b ") & cr & " - 0 1"
End Function

Private Sub UpdateEngine()
    If AZ.editing Then Exit Sub
    Dim As Boolean changed = (AZ.resultKey <> AZ.pos.hash) OrElse (AZ.resultPly <> AZ.pos.historyCount)
    If changed Then
        ResetEngine()
        AZ.resultKey = AZ.pos.hash
        AZ.resultPly = AZ.pos.historyCount
        If Pos_HasLegalMove(AZ.pos) Then
            Dim As EngineParams prm
            Engine_LevelParams(LEVEL_ADVANCED, STYLE_BALANCED, prm)
            prm.timeLimitMs = 3000 : prm.bookPlies = 0 : prm.contempt = 0
            Engine_StartAsync(AZ.pos, prm)
            AZ.thinking = True
        End If
    End If
    If AZ.thinking AndAlso Engine_PollAsync(AZ.result) Then
        AZ.thinking = False
        AZ.resultValid = True
    End If
End Sub

Function Analyze_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_ANALYZE
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    UI.blockInput = AZInput.active
    UI_DrawBackground()
    Screen_DrawHeader(IIf(AZ.editing, "Set up a position", "Analyze Position"))
    UpdateEngine()
    If AZ.thinking Then UI_KeepFast(0.2)

    '' ---- Board ----
    AZBoard.theme = AppConfig.boardTheme
    AZBoard.pieceSet = AppConfig.pieceSet
    AZBoard.showCoords = AppConfig.showCoordinates
    AZBoard.flipped = AZ.flipped
    Board_Layout(AZBoard, 0, 0, 10)
    Dim As Integer sq = (sh - 74 - 2 * AZBoard.margin) \ 8
    If sq * 8 + 2 * AZBoard.margin > sw - 470 - 2 * AZBoard.margin Then sq = (sw - 470 - 2 * AZBoard.margin) \ 8
    Board_Layout(AZBoard, 0, 0, sq)
    Dim As Integer outer = Board_OuterSize(AZBoard)
    Board_Layout(AZBoard, 44, 50 + (sh - 50 - outer) \ 2, sq)

    Dim As BoardMarks extra
    Board_ClearMarks(extra)
    If Not AZ.editing Then
        If AZ.resultValid AndAlso AZ.result.bestMove.piece <> PC_EMPTY Then
            Board_AddArrow(extra, AZ.result.bestMove.fromSq, AZ.result.bestMove.toSq, MARK_GREEN)
        End If
        If AZ.showThreats Then
            Dim As Integer th(0 To 127), s, side
            For side = 0 To 1
                Coach_ThreatenedPieces(AZ.pos, side, th())
                For s = 0 To 127
                    If th(s) > 0 Then extra.highlight(s) = MARK_RED
                Next
            Next
        End If
    End If
    Dim As ChessMove m
    Dim As String illegal
    Dim As Boolean canMove = Not AZ.editing AndAlso AZ.pos.kingSq(0) <> NO_SQUARE
    If BC_Frame(AZBC, AZBoard, AZ.pos, canMove, extra, m, illegal) Then
        Pos_MakeMove(AZ.pos, m)
        BC_AnimateMove(AZBC, AZ.pos, m)
        AZ.message = ""
    End If
    If illegal <> "" Then AZ.message = illegal

    '' Editor: click squares to place the selected piece
    If AZ.editing AndAlso UI.pressed Then
        Dim As Integer s = Board_SquareAt(AZBoard, UI.mx, UI.my)
        If s <> NO_SQUARE Then
            If AZ.pos.board(s) = AZ.palette Then AZ.pos.board(s) = PC_EMPTY Else AZ.pos.board(s) = AZ.palette
            '' Keep the king squares up to date for drawing.
            AZ.pos.kingSq(0) = NO_SQUARE : AZ.pos.kingSq(1) = NO_SQUARE
            Dim As Integer t
            For t = 0 To 127
                If Not SQ_OFFBOARD(t) Then
                    If AZ.pos.board(t) = PC_WK Then AZ.pos.kingSq(0) = t
                    If AZ.pos.board(t) = PC_BK Then AZ.pos.kingSq(1) = t
                End If
            Next
        End If
    End If

    '' Evaluation bar (left of the board)
    If Not AZ.editing Then
        Dim As Integer bx = 14, by = AZBoard.y, bh = sq * 8
        Dim As Integer ws = 0
        If AZ.resultValid Then ws = IIf(AZ.pos.sideToMove = SIDE_WHITE, AZ.result.score, -AZ.result.score)
        Dim As Double wc = 100.0 / (1 + 10 ^ (-IIf(ws > 2000, 2000, IIf(ws < -2000, -2000, ws)) / 400.0))
        Dim As Integer whiteH = bh * wc / 100
        If AZ.flipped Then
            Gfx_FillRect(bx, by, 18, whiteH, RGB(245, 242, 232))
            Gfx_FillRect(bx, by + whiteH, 18, bh - whiteH, RGB(50, 50, 56))
        Else
            Gfx_FillRect(bx, by, 18, bh - whiteH, RGB(50, 50, 56))
            Gfx_FillRect(bx, by + bh - whiteH, 18, whiteH, RGB(245, 242, 232))
        End If
        If UI_Hover(bx, by, 18, bh) Then UI_SetTooltip("az.bar", "Evaluation bar: the more white, the better for White.")
    End If

    '' ---- Panel ----
    Dim As Integer px = 44 + outer + 20, pw = sw - px - 16, y = 62
    Gfx_Panel(px, y, pw, sh - y - 16, 14, RGB(252, 249, 240), RGB(150, 120, 80))
    Dim As Integer tx = px + 16, tw = pw - 32, bwid = (tw - 8) \ 2, bh2 = 40
    Dim As Integer btnTop = sh - 16 - 3 * 48

    If AZ.editing Then
        Text_DrawWrapped(tx, y + 12, tw, "Choose a piece, then click squares to place it. Click again to remove it.", 18, RGB(60, 50, 30))
        If AZPieces.size <> 44 OrElse AZPieces.style <> AppConfig.pieceSet Then Pieces_Build(AZPieces, 44, AppConfig.pieceSet)
        Dim As Integer i, side
        For side = 0 To 1
            For i = PT_PAWN To PT_KING
                Dim As Integer pcode = MAKE_PIECE(side, i)
                Dim As Integer cx = tx + (i - 1) * 52, cy = y + 66 + side * 54
                Dim As Boolean selected = (AZ.palette = pcode)
                Gfx_Panel(cx, cy, 48, 48, 8, IIf(selected, RGB(255, 226, 120), RGB(236, 226, 206)), _
                          IIf(selected, RGB(200, 140, 20), RGB(150, 120, 80)), False)
                Pieces_Draw(AZPieces, pcode, cx + 2, cy + 2)
                If UI_Hover(cx, cy, 48, 48) AndAlso UI.pressed Then AZ.palette = pcode
            Next
        Next
        Dim As Integer ey = y + 182
        If UI_Button("az.erase", tx, ey, bwid, bh2, "Eraser", True, "Remove pieces by clicking them.", _
                     IIf(AZ.palette = PC_EMPTY, BTN_PRIMARY, BTN_NORMAL)) Then AZ.palette = PC_EMPTY
        If UI_Button("az.clear", tx + bwid + 8, ey, bwid, bh2, "Clear board", True, "Remove all pieces.") Then
            Dim As Integer t
            For t = 0 To 127
                AZ.pos.board(t) = PC_EMPTY
            Next
            AZ.pos.kingSq(0) = NO_SQUARE : AZ.pos.kingSq(1) = NO_SQUARE
        End If
        If UI_Button("az.startpos", tx, ey + 48, bwid, bh2, "Start position", True, "The normal starting position.") Then
            Dim As Integer keepSide = AZ.editSide
            Pos_SetStart(AZ.pos)
            AZ.editSide = keepSide
        End If
        Text_Draw(tx, ey + 106, "To move:", 20, RGB(60, 50, 30))
        UI_Selector("az.side", tx + 110, ey + 96, tw - 110, bh2, "White|Black", AZ.editSide, True, "Who moves first?")
        If AZ.message <> "" Then Text_DrawWrapped(tx, ey + 152, tw, AZ.message, 17, RGB(180, 50, 30))
        If UI_Button("az.done", tx, btnTop + 96, bwid, bh2, "Done", True, "Check the position and start analysing.", BTN_PRIMARY) Then
            Dim As String e, fen = EditorFEN()
            Static test As Position
            If Pos_LoadFEN(test, fen, e) Then
                Pos_LoadFEN(AZ.pos, fen, e)
                AZ.editing = False
                AZ.message = ""
                BC_Reset(AZBC)
                ResetEngine()
                AZ.resultPly = -1
            Else
                AZ.message = "This position cannot be used: " & e
            End If
        End If
        If UI_Button("az.cancel", tx + bwid + 8, btnTop + 96, bwid, bh2, "Cancel", True, "Leave the editor without changes.") Then
            AZ.editing = False
            Dim As String e
            If Not Pos_LoadFEN(AZ.pos, AZ.beforeEdit, e) Then Pos_SetStart(AZ.pos)
            ResetEngine()
            AZ.resultPly = -1
            AZ.message = ""
        End If
    Else
        '' Evaluation and best move
        Text_Draw(tx, y + 12, IIf(AZ.pos.sideToMove = SIDE_WHITE, "White", "Black") & " to move", 22, RGB(80, 52, 24))
        Dim As String evalLine, bestLine = "", explain = "", pv = ""
        If Not Pos_HasLegalMove(AZ.pos) Then
            evalLine = IIf(Pos_InCheck(AZ.pos), "Checkmate!", "Stalemate - a draw.")
        ElseIf AZ.resultValid Then
            Dim As Integer ws = IIf(AZ.pos.sideToMove = SIDE_WHITE, AZ.result.score, -AZ.result.score)
            evalLine = Coach_EvalText(ws)
            bestLine = "Best move: " & Notation_MoveToSAN(AZ.pos, AZ.result.bestMove)
            If AZ.explainKey <> AZ.pos.hash Then
                AZ.explainKey = AZ.pos.hash
                AZ.explainText = Coach_ExplainMove(AZ.pos, AZ.result.bestMove)
                Static q As Position
                q = AZ.pos
                Dim As Integer k
                AZ.pvText = ""
                For k = 0 To AZ.result.pvLen - 1
                    If k >= 8 Then Exit For
                    Dim As ChessMove pm = AZ.result.pv(k)
                    Dim As ChessMove chk
                    If Not Pos_FindLegalMove(q, pm.fromSq, pm.toSq, pm.promotion, chk) Then Exit For
                    AZ.pvText &= Notation_MoveToSAN(q, chk) & " "
                    Pos_MakeMove(q, chk)
                Next
            End If
            explain = AZ.explainText
            pv = AZ.pvText
        Else
            evalLine = "Thinking" & String(Int(Timer * 3) Mod 4, ".")
        End If
        Text_DrawWrapped(tx, y + 46, tw, evalLine, 20, RGB(52, 100, 170))
        If bestLine <> "" Then
            Text_Draw(tx, y + 90, bestLine, 22, RGB(30, 110, 50))
            Dim As Integer es = Text_FitSize(explain, tw, 90, 18, 13)
            Text_DrawWrapped(tx, y + 122, tw, explain, es, RGB(60, 50, 30))
            Text_DrawWrapped(tx, y + 216, tw, "Main line: " & pv, 15, RGB(120, 105, 90))
            Text_Draw(tx, y + 262, "depth " & AZ.result.depth & IIf(AZ.thinking, "  (thinking...)", ""), 14, RGB(150, 140, 130))
        End If
        If AZ.message <> "" Then Text_DrawWrapped(tx, y + 290, tw, AZ.message, 16, RGB(180, 50, 30))

        Dim As Integer row = btnTop - 2 * 48
        If UI_Button("az.edit", tx, row, bwid, bh2, "Set up position", True, "Place pieces on an empty board or change this position.") Then
            ResetEngine()
            AZ.beforeEdit = Pos_GetFEN(AZ.pos)
            AZ.editing = True
            AZ.editSide = AZ.pos.sideToMove
            AZ.message = ""
            BC_Reset(AZBC)
        End If
        If UI_Button("az.threats", tx + bwid + 8, row, bwid, bh2, "Threats", True, "Mark pieces that can be won (red).", _
                     IIf(AZ.showThreats, BTN_PRIMARY, BTN_NORMAL)) Then AZ.showThreats = Not AZ.showThreats
        row += 48
        If UI_Button("az.paste", tx, row, bwid, bh2, "Enter FEN", True, "Type or paste a position in FEN notation.") Then
            InputDialog_Open(AZInput, "fen", "Position (FEN)", "Type or paste a FEN position:", "", "OK|Paste|Cancel", 100)
        End If
        If UI_Button("az.copy", tx + bwid + 8, row, bwid, bh2, "Copy FEN", True, "Copy this position (FEN) to the clipboard.") Then
            If Clipboard_SetText(Pos_GetFEN(AZ.pos)) Then AZ.message = "Copied: " & Pos_GetFEN(AZ.pos) _
            Else AZ.message = Pos_GetFEN(AZ.pos)
        End If
        row += 48
        Dim As Boolean canUndo = AZ.pos.historyCount > AZ.baseHistory
        If UI_Button("az.undo", tx, row, (tw - 16) \ 3, bh2, "Undo", canUndo, "Take back the last move made here.") Then
            Pos_UnmakeMove(AZ.pos)
            BC_Reset(AZBC)
        End If
        If UI_Button("az.flip", tx + (tw - 16) \ 3 + 8, row, (tw - 16) \ 3, bh2, "Flip", True, "Turn the board (F).") Then
            AZ.flipped = Not AZ.flipped
        End If
        If UI_Button("az.play", tx + 2 * ((tw - 16) \ 3 + 8), row, (tw - 16) \ 3, bh2, "Play", Pos_HasLegalMove(AZ.pos), _
                     "Play this position against the computer.") Then
            Dim As String e
            Engine_StopAsync()
            If Play_StartFromFEN(NewGameOpts, Pos_GetFEN(AZ.pos), e) Then nextScreen = SCREEN_PLAY Else AZ.message = e
        End If
        row += 48
        If UI_Button("az.back", tx, row, tw, bh2, "Back", True, "Leave the analysis (Esc).") OrElse _
           (CBool(UI.keyCode = KEY_ESCAPE) AndAlso Not AZInput.active) Then
            ResetEngine()
            nextScreen = AZ.returnTo
        End If
        If CBool(UI.keyCode = Asc("f")) OrElse CBool(UI.keyCode = Asc("F")) Then AZ.flipped = Not AZ.flipped
    End If

    If AZInput.active Then
        Select Case InputDialog_Run(AZInput)
        Case 0
            Dim As String e
            Static test2 As Position
            If Pos_LoadFEN(test2, Trim(AZInput.text), e) Then
                Pos_LoadFEN(AZ.pos, Trim(AZInput.text), e)
                AZ.baseHistory = 0
                AZ.flipped = (AZ.pos.sideToMove = SIDE_BLACK)
                BC_Reset(AZBC)
                ResetEngine()
                AZ.resultPly = -1
                AZInput.active = False
            Else
                AZInput.errorText = "That position cannot be used: " & e
            End If
        Case 1 : InputDialog_Paste(AZInput)
        Case 2 : AZInput.active = False
        End Select
    End If
    Return nextScreen
End Function
