'' =====================================================================
'' BeginnerChess - review.bas
'' Game Review: BeginnerChess's engine looks at every move of a game and
'' marks it Best / Good / Inaccuracy / Mistake / Blunder, shows how the
'' advantage changed (graph), the turning points and better moves with
'' an explanation. All of this is an educational estimate.
'' =====================================================================
#include once "screens.bi"
#include once "boardctl.bi"
#include once "analysis.bi"
#include once "coach.bi"

Type ReviewState
    g          As ChessGame
    ply        As Integer          '' position shown = after 'ply' moves
    pos        As Position
    returnTo   As Integer
    listScroll As Integer
    flipped    As Boolean
    cancelled  As Boolean
    cachePly   As Integer          '' details text computed for this position
    cacheHead  As String
    cacheBody  As String
    cacheClass As Integer
End Type
Dim Shared RV As ReviewState
Dim Shared RVBoard As BoardView
Dim Shared RVBC As BoardControl

Private Function ClassColor(ByVal c As Integer) As ULong
    Select Case c
    Case MC_BEST       : Return RGB(40, 150, 60)
    Case MC_GOOD       : Return RGB(110, 170, 90)
    Case MC_INACCURACY : Return RGB(220, 170, 20)
    Case MC_MISTAKE    : Return RGB(230, 120, 30)
    Case MC_BLUNDER    : Return RGB(210, 40, 30)
    Case MC_BOOK       : Return RGB(140, 120, 90)
    End Select
    Return RGB(150, 150, 150)
End Function

Private Function ClassMark(ByVal c As Integer) As String
    Select Case c
    Case MC_INACCURACY : Return "?!"
    Case MC_MISTAKE    : Return "?"
    Case MC_BLUNDER    : Return "??"
    End Select
    Return ""
End Function

Private Sub SetPly(ByVal ply As Integer)
    If ply < 0 Then ply = 0
    If ply > RV.g.moveCount Then ply = RV.g.moveCount
    RV.ply = ply
    Analysis_PositionBefore(ply, RV.pos)
    BC_Reset(RVBC)
    If ply > 0 Then
        Dim As ChessMove m = Analysis_PlayedMove(ply - 1)
        RVBC.lastFrom = m.fromSq
        RVBC.lastTo = m.toSq
    End If
End Sub

Sub Review_Start(ByRef g As ChessGame, ByVal returnScreen As Integer, ByVal flipped As Boolean)
    Engine_StopAsync()
    RV.g = g
    RV.returnTo = returnScreen
    RV.flipped = flipped
    RV.listScroll = 0
    RV.cancelled = False
    RV.cachePly = -1
    Analysis_Begin(g, 250)
    SetPly(0)
End Sub

'' Index of the next inaccuracy, mistake or blunder after ply 'from' (or -1).
Private Function NextTurningPoint(ByVal from As Integer) As Integer
    Dim As Integer i
    For i = from + 1 To RV.g.moveCount - 1
        Dim As Integer c = Analysis_Class(i)
        If c >= MC_INACCURACY AndAlso c <> MC_BOOK Then Return i
    Next
    '' Wrap around to the first one.
    For i = 0 To from
        Dim As Integer c2 = Analysis_Class(i)
        If c2 >= MC_INACCURACY AndAlso c2 <> MC_BOOK AndAlso i <> from Then Return i
    Next
    Return -1
End Function

Function Review_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_REVIEW
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    UI_DrawBackground()
    Screen_DrawHeader("Game Review")

    '' ---- Still analysing: one position per frame ----
    If Not Analysis_Done() AndAlso Not RV.cancelled Then
        Analysis_Step()
        UI_KeepFast()
        Dim As Integer w = 560, h = 190, x = (sw - w) \ 2, y = (sh - h) \ 2
        Gfx_Panel(x, y, w, h, 16, RGB(252, 248, 238), RGB(110, 84, 50))
        Text_DrawCentered(x + w \ 2, y + 22, "The computer is studying the game...", 24, RGB(80, 52, 24))
        Gfx_RoundRect(x + 40, y + 76, w - 80, 26, 13, RGB(220, 214, 200))
        Gfx_RoundRect(x + 40, y + 76, (w - 80) * Analysis_Progress() \ 100, 26, 13, RGB(52, 120, 206))
        Text_DrawCentered(x + w \ 2, y + 80, Analysis_Progress() & "%", 18, RGB(255, 255, 255))
        If UI_Button("rv.cancel", x + w \ 2 - 70, y + h - 64, 140, 44, "Cancel", True, "Stop the review.") _
           OrElse UI.keyCode = KEY_ESCAPE Then
            RV.cancelled = True
            nextScreen = RV.returnTo
        End If
        Return nextScreen
    End If

    '' ---- Board with arrows: the move played (red if it was a mistake) and a better one ----
    RVBoard.theme = AppConfig.boardTheme
    RVBoard.pieceSet = AppConfig.pieceSet
    RVBoard.showCoords = AppConfig.showCoordinates
    RVBoard.flipped = RV.flipped
    Board_Layout(RVBoard, 0, 0, 10)
    Dim As Integer sq = (sh - 74 - 2 * RVBoard.margin) \ 8
    If sq * 8 + 2 * RVBoard.margin > sw - 448 - 2 * RVBoard.margin Then sq = (sw - 448 - 2 * RVBoard.margin) \ 8
    Board_Layout(RVBoard, 0, 0, sq)
    Dim As Integer outer = Board_OuterSize(RVBoard)
    Board_Layout(RVBoard, 16, 50 + (sh - 50 - outer) \ 2, sq)
    Dim As BoardMarks extra
    Board_ClearMarks(extra)
    Dim As Integer cur = RV.ply - 1                 '' the move that led to this position
    Dim As Integer nextMove = RV.ply                '' the move about to be played here
    If nextMove < RV.g.moveCount Then
        Dim As Integer c = Analysis_Class(nextMove)
        Dim As ChessMove played = Analysis_PlayedMove(nextMove), best = Analysis_BestMove(nextMove)
        If c >= MC_INACCURACY AndAlso c <> MC_BOOK Then
            Board_AddArrow(extra, played.fromSq, played.toSq, MARK_RED)
            If best.piece <> PC_EMPTY Then Board_AddArrow(extra, best.fromSq, best.toSq, MARK_GREEN)
        Else
            Board_AddArrow(extra, played.fromSq, played.toSq, MARK_BLUE)
        End If
    End If
    Dim As ChessMove dummy
    Dim As String illegal
    BC_Frame(RVBC, RVBoard, RV.pos, False, extra, dummy, illegal)

    '' ---- Panel ----
    Dim As Integer px = 16 + outer + 20, pw = sw - px - 16, y = 62
    Gfx_Panel(px, y, pw, sh - y - 16, 14, RGB(252, 249, 240), RGB(150, 120, 80))
    Dim As Integer tx = px + 14, tw = pw - 28

    '' Summary per side
    Dim As Integer counts(0 To 1, 0 To 5), i, side
    Dim As Position first
    Analysis_PositionBefore(0, first)
    side = first.sideToMove
    For i = 0 To RV.g.moveCount - 1
        Dim As Integer c = Analysis_Class(i)
        If c >= 0 Then counts(side, c) += 1
        side Xor= 1
    Next
    Dim As String labels(0 To 4) = {"Best", "Good", "Inacc.", "Mistake", "Blunder"}
    Text_Draw(tx, y + 10, "Review (estimates)", 20, RGB(80, 52, 24))
    Dim As Integer colW = (tw - 70) \ 5
    For i = 0 To 4
        Text_DrawCentered(tx + 70 + i * colW + colW \ 2, y + 38, labels(i), 14, ClassColor(i))
    Next
    For side = 0 To 1
        Dim As Integer ry = y + 58 + side * 22
        Text_Draw(tx, ry, IIf(side = 0, "White", "Black"), 16, RGB(60, 50, 40))
        For i = 0 To 4
            Text_DrawCentered(tx + 70 + i * colW + colW \ 2, ry, Str(counts(side, i)), 16, ClassColor(i))
        Next
    Next

    '' Advantage graph (White up, Black down); click to jump to a move.
    Dim As Integer gx = tx, gy = y + 108, gw = tw, gh = 70
    Gfx_FillRect(gx, gy, gw, gh, RGB(60, 60, 66))
    Gfx_FillRect(gx, gy + gh \ 2, gw, gh \ 2, RGB(230, 226, 216))
    Dim As Integer n = RV.g.moveCount
    If n > 0 Then
        Dim As Integer k, prevX = gx, prevY = gy + gh \ 2
        For k = 0 To n - 1
            Dim As Integer xx = gx + (k + 1) * gw \ n
            Dim As Double wc = Analysis_WinChance(Analysis_WhiteScore(k))
            Dim As Integer yy = gy + gh - CInt(wc * gh / 100)
            '' White's area in light colour above the curve's mirror
            Gfx_FillRect(prevX, yy, xx - prevX + 1, gy + gh - yy, RGB(245, 242, 232))
            Gfx_FillRect(prevX, gy, xx - prevX + 1, yy - gy, RGB(60, 60, 66))
            Dim As Integer c = Analysis_Class(k)
            If c = MC_MISTAKE OrElse c = MC_BLUNDER Then Gfx_FillCircle(xx, yy, 3, ClassColor(c))
            prevX = xx : prevY = yy
        Next
        Dim As Integer mx = gx + RV.ply * gw \ n
        Gfx_FillRect(mx - 1, gy, 2, gh, RGB(52, 120, 206))
        If UI_Hover(gx, gy, gw, gh) AndAlso UI.down Then SetPly(((UI.mx - gx) * n + gw \ 2) \ gw)
    End If
    Gfx_FillRect(gx, gy + gh \ 2, gw, 1, RGB(150, 150, 150))

    '' Details of the move played from this position
    Dim As Integer dy = gy + gh + 10, dh = 128
    Gfx_Panel(tx - 4, dy, tw + 8, dh, 10, RGB(255, 250, 225), RGB(200, 170, 80), False)
    Dim As String head = "", body = ""
    If RV.cachePly = RV.ply Then
        If RV.cacheHead <> "" Then Text_Draw(tx + 4, dy + 8, RV.cacheHead, 20, ClassColor(RV.cacheClass))
        body = RV.cacheBody
    ElseIf nextMove < RV.g.moveCount Then
        Dim As Integer c = Analysis_Class(nextMove)
        Dim As Position before
        Analysis_PositionBefore(nextMove, before)
        Dim As ChessMove played = Analysis_PlayedMove(nextMove), best = Analysis_BestMove(nextMove)
        Dim As String num = before.fullmoveNumber & IIf(before.sideToMove = SIDE_WHITE, ". ", "... ")
        head = num & RV.g.sanMoves(nextMove) & "  -  " & Analysis_ClassName(c)
        If c = MC_BOOK Then
            body = "A well-known opening move."
        ElseIf c >= MC_INACCURACY AndAlso best.piece <> PC_EMPTY Then
            Dim As String bestSan = Notation_MoveToSAN(before, best)
            body = "Better was " & bestSan & ": " & Coach_ExplainMove(before, best)
            '' What went wrong with the move played?
            Dim As Position after = before
            Pos_MakeMove(after, played)
            If Pos_HasLegalMove(after) Then
                Dim As EngineParams prm
                Engine_LevelParams(LEVEL_NORMAL, STYLE_BALANCED, prm)
                prm.maxDepth = 3 : prm.timeLimitMs = 100 : prm.bookPlies = 0 : prm.temperature = 0 : prm.noise = 0
                Dim As EngineResult r
                If Engine_Search(after, prm, r) AndAlso c >= MC_MISTAKE Then
                    body &= "|After " & RV.g.sanMoves(nextMove) & ": " & Coach_ExplainThreat(after, r.bestMove)
                End If
            End If
        Else
            body = Coach_ExplainMove(before, played)
        End If
        Text_Draw(tx + 4, dy + 8, head, 20, ClassColor(c))
        RV.cachePly = RV.ply : RV.cacheHead = head : RV.cacheBody = body : RV.cacheClass = c
    Else
        Text_Draw(tx + 4, dy + 8, "End of the game", 20, RGB(80, 52, 24))
        body = Game_StatusText(RV.g)
    End If
    Dim As Integer bs = Text_FitSize(body, tw - 8, dh - 44, 18, 13)
    Text_DrawWrapped(tx + 4, dy + 36, tw - 8, body, bs, RGB(60, 50, 30))

    '' Evaluation in words
    Dim As Integer ey = dy + dh + 8
    Text_DrawWrapped(tx, ey, tw, Coach_EvalText(Analysis_WhiteScore(RV.ply - 1)), 16, RGB(52, 100, 170))

    '' Move list with marks
    Dim As Integer btnTop = sh - 16 - 3 * 48
    Dim As Integer ly = ey + 26, lh = btnTop - 8 - ly
    Gfx_Panel(tx - 4, ly, tw + 8, lh, 8, RGB(255, 255, 255), RGB(150, 130, 100), False)
    Dim As Integer rowH = 20, visible = (lh - 8) \ rowH
    Dim As Integer offset = IIf(first.sideToMove = SIDE_BLACK, 1, 0)
    Dim As Integer rows = (n + offset + 1) \ 2
    Dim As Integer curRow = (RV.ply - 1 + offset) \ 2
    If RV.ply > 0 Then
        If curRow < RV.listScroll Then RV.listScroll = curRow
        If curRow >= RV.listScroll + visible Then RV.listScroll = curRow - visible + 1
    End If
    If UI_Hover(tx, ly, tw, lh) AndAlso UI.wheelDelta <> 0 Then RV.listScroll -= UI.wheelDelta * 2
    If RV.listScroll > rows - visible Then RV.listScroll = rows - visible
    If RV.listScroll < 0 Then RV.listScroll = 0
    Dim As Integer r, c2
    For r = RV.listScroll To RV.listScroll + visible - 1
        If r >= rows Then Exit For
        Dim As Integer ry = ly + 4 + (r - RV.listScroll) * rowH
        Text_Draw(tx, ry + 2, (first.fullmoveNumber + r) & ".", 15, RGB(140, 120, 100))
        For c2 = 0 To 1
            Dim As Integer pl = r * 2 + c2 - offset
            If pl < 0 OrElse pl >= n Then Continue For
            Dim As Integer cx = tx + 40 + c2 * ((tw - 44) \ 2), cw = (tw - 44) \ 2 - 4
            If pl = RV.ply - 1 Then Gfx_RoundRect(cx - 3, ry, cw, rowH - 2, 4, RGB(255, 226, 120))
            Dim As Integer cls2 = Analysis_Class(pl)
            Text_Draw(cx, ry + 2, RV.g.sanMoves(pl) & ClassMark(cls2), 15, _
                      IIf(cls2 >= MC_INACCURACY AndAlso cls2 <> MC_BOOK, ClassColor(cls2), RGB(30, 30, 40)))
            If UI_Hover(cx - 3, ry, cw, rowH) AndAlso UI.pressed Then SetPly(pl + 1)
        Next
    Next

    '' Controls
    Dim As Integer bw = (tw - 24) \ 4, bh = 40
    If UI_Button("rv.first", tx, btnTop, bw, bh, "|<", True, "Start (Home)") Then SetPly(0)
    If UI_Button("rv.prev", tx + bw + 8, btnTop, bw, bh, "<", True, "Previous move (Left)") Then SetPly(RV.ply - 1)
    If UI_Button("rv.next", tx + 2 * (bw + 8), btnTop, bw, bh, ">", True, "Next move (Right)") Then SetPly(RV.ply + 1)
    If UI_Button("rv.last", tx + 3 * (bw + 8), btnTop, bw, bh, ">|", True, "End (End)") Then SetPly(n)
    Dim As Integer tp = NextTurningPoint(RV.ply - 1)
    If UI_Button("rv.turn", tx, btnTop + 48, (tw - 8) \ 2, bh, "Next mistake", tp >= 0, _
                 IIf(tp >= 0, "Jump to the next move that could have been better.", "No more mistakes in this game!"), BTN_PRIMARY) Then SetPly(tp)
    If UI_Button("rv.flip", tx + (tw - 8) \ 2 + 8, btnTop + 48, (tw - 8) \ 2, bh, "Flip", True, "Turn the board (F).") Then
        RV.flipped = Not RV.flipped
    End If
    Dim As Boolean goBack = UI_Button("rv.back", tx, btnTop + 96, tw, bh, "Done", True, "Leave the review (Esc).")
    Select Case UI.keyCode
    Case KEY_RIGHT : SetPly(RV.ply + 1)
    Case KEY_LEFT : SetPly(RV.ply - 1)
    Case 1071 : SetPly(0)
    Case 1079 : SetPly(n)
    Case Asc("f"), Asc("F") : RV.flipped = Not RV.flipped
    Case KEY_ESCAPE : goBack = True
    End Select
    If goBack Then nextScreen = RV.returnTo
    Return nextScreen
End Function

'' Screenshot helper: finish the analysis at once and show a ply.
Sub Review_DebugFinish(ByVal ply As Integer)
    Do Until Analysis_Step() : Loop
    SetPly(ply)
End Sub
