'' =====================================================================
'' BeginnerChess - famousui.bas
'' Famous Games: the library list and the move-by-move game viewer.
'' =====================================================================
#include once "screens.bi"
#include once "boardctl.bi"
#include once "famous.bi"

'' ---------------------------------------------------------------------
'' Library list
'' ---------------------------------------------------------------------
Dim Shared FLFilter As Integer = 0          '' 0 all, 1 <1900, 2 1900-1949, 3 >=1950, 4 my games
Dim Shared FLScroll As Integer = 0
Dim Shared FLDlg As DialogState
Dim Shared FLPendingDelete As Integer = -1

Declare Sub Viewer_Start(ByVal index As Integer)

Private Function PassesFilter(ByVal i As Integer) As Boolean
    Dim As FamousGame Ptr fg = Famous_Get(i)
    Select Case FLFilter
    Case 1 : Return fg->year > 0 AndAlso fg->year < 1900
    Case 2 : Return fg->year >= 1900 AndAlso fg->year < 1950
    Case 3 : Return fg->year >= 1950
    Case 4 : Return fg->source = "user"
    End Select
    Return True
End Function

Function FamousList_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_FAMOUS
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    UI.blockInput = FLDlg.active
    UI_DrawBackground()
    Screen_DrawHeader("Famous Games")
    Text_Draw(24, 62, "Replay great games from chess history - and learn from the masters!", 20, RGB(240, 230, 210))

    '' Filters
    Dim As String names(0 To 4) = {"All games", "Before 1900", "1900 - 1949", "1950 and later", "My games"}
    Dim As Integer f, cx = 24, cw = 220
    For f = 0 To 4
        If UI_Button("fl.f" & f, cx, 100 + f * 50, cw, 42, names(f), True, "", IIf(f = FLFilter, BTN_PRIMARY, BTN_MENU)) Then
            FLFilter = f : FLScroll = 0
        End If
    Next
    Text_DrawWrapped(cx, 360, cw, Famous_StatusText(), 15, _
                     IIf(Famous_UsingDatabase(), RGB(160, 200, 170), RGB(240, 170, 120)))

    '' Games
    Dim As Integer lx = cx + cw + 20, lw = sw - lx - 24, ly = 100, rowH = 64
    Dim As Integer visible = (sh - 96 - ly) \ rowH
    Dim As Integer ids(0 To 999), n = 0, i
    For i = 0 To Famous_Count() - 1
        If PassesFilter(i) AndAlso n < 1000 Then ids(n) = i : n += 1
    Next
    If UI_Hover(lx, ly, lw, visible * rowH) AndAlso UI.wheelDelta <> 0 Then FLScroll -= UI.wheelDelta * 2
    If FLScroll > n - visible Then FLScroll = n - visible
    If FLScroll < 0 Then FLScroll = 0
    If n = 0 Then
        Text_DrawWrapped(lx, ly + 10, lw, IIf(FLFilter = 4, _
            "You have not added any games yet. Use 'Add PGN file' to put your own games into the library.", _
            "No games in this group."), 20, RGB(220, 220, 230))
    End If
    For i = FLScroll To FLScroll + visible - 1
        If i >= n Then Exit For
        Dim As FamousGame Ptr fg = Famous_Get(ids(i))
        Dim As Integer y = ly + (i - FLScroll) * rowH
        Dim As Boolean isUser = (fg->source = "user")
        Dim As Integer rowW = IIf(isUser, lw - 110, lw)
        If UI_Button("fl.g" & ids(i), lx, y, rowW, rowH - 8, "", True, _
                     IIf(fg->intro <> "", fg->intro, "Replay this game move by move."), BTN_MENU) Then
            Viewer_Start(ids(i))
            nextScreen = SCREEN_VIEWER
        End If
        Dim As String title = fg->white & " - " & fg->black
        Dim As Integer ts = 21
        Do While ts > 14 AndAlso Text_Width(title, ts) > rowW - 120
            ts -= 1
        Loop
        Text_Draw(lx + 14, y + 8, title, ts, RGB(70, 46, 22))
        Dim As String sub1 = fg->event & IIf(fg->year > 0, ", " & fg->year, "") & _
                             IIf(fg->opening <> "", "  -  " & fg->opening, "")
        If Text_Width(sub1, 15) > rowW - 120 Then sub1 = Left(sub1, (rowW - 130) \ 7) & "..."
        Text_Draw(lx + 14, y + 36, sub1, 15, RGB(120, 100, 80))
        Text_Draw(lx + rowW - 96, y + 18, fg->result, 20, RGB(52, 100, 170))
        If isUser Then
            If UI_Button("fl.del" & ids(i), lx + lw - 100, y + 8, 100, rowH - 24, "Remove", True, _
                         "Remove this game from your library.") Then
                FLPendingDelete = ids(i)
                Dialog_Open(FLDlg, "del", "Remove game?", "Remove '" & title & "' from your library?", "Remove|Cancel")
            End If
        End If
    Next
    If n > visible Then Text_Draw(lx, sh - 50, "Scroll with the mouse wheel for more games.", 16, RGB(160, 176, 200))

    If UI_Button("fl.add", sw - 264, sh - 64, 240, 46, "Add PGN file", Famous_UsingDatabase(), _
                 IIf(Famous_UsingDatabase(), "Add all games of a PGN file to your library.", _
                     "Adding games needs the SQLite database."), BTN_PRIMARY) Then
        Import_Begin(SCREEN_FAMOUS, 1)
        nextScreen = SCREEN_IMPORT
    End If
    Dim As Boolean goBack = UI_Button("fl.back", 20, sh - 64, 140, 46, "< Back", True, "Return to the main menu.")
    If UI.keyCode = KEY_ESCAPE AndAlso Not FLDlg.active Then goBack = True
    If goBack Then nextScreen = SCREEN_MENU

    If FLDlg.active Then
        Dim As Integer r = Dialog_Run(FLDlg)
        If r = 0 AndAlso FLPendingDelete >= 0 Then Famous_Delete(FLPendingDelete)
        If r >= 0 Then FLPendingDelete = -1
    End If
    Return nextScreen
End Function

'' ---------------------------------------------------------------------
'' Game viewer
'' ---------------------------------------------------------------------
Type ViewerState
    index      As Integer
    g          As ChessGame
    pos        As Position
    ply        As Integer
    autoPlay   As Boolean
    nextAt     As Double
    speed      As Integer      '' 0 slow, 1 normal, 2 fast
    flipped    As Boolean
    listScroll As Integer
    errorText  As String
    sawEnd     As Boolean
    ext        As FamousGame   '' header of a game from a PGN file (index = -1)
    returnTo   As Integer      '' screen for "Back"
End Type
Dim Shared VW As ViewerState
Dim Shared ViewBoard As BoardView
Dim Shared ViewBC As BoardControl

'' Shows the position after 'ply' half-moves (animated when stepping forward by one).
Private Sub SetPly(ByVal ply As Integer, ByVal animate As Boolean)
    If ply < 0 Then ply = 0
    If ply > VW.g.moveCount Then ply = VW.g.moveCount
    If animate AndAlso ply = VW.ply + 1 Then
        Dim As ChessMove m = VW.g.pos.undoStack(VW.ply).mv
        Pos_MakeMove(VW.pos, m)
        BC_AnimateMove(ViewBC, VW.pos, m)
        VW.ply = ply
        Exit Sub
    End If
    Dim As String e
    Pos_LoadFEN(VW.pos, VW.g.startFEN, e)
    Dim As Integer i
    For i = 0 To ply - 1
        Pos_MakeMove(VW.pos, VW.g.pos.undoStack(i).mv)
    Next
    VW.ply = ply
    BC_Reset(ViewBC)
    If ply > 0 Then
        ViewBC.lastFrom = VW.g.pos.undoStack(ply - 1).mv.fromSq
        ViewBC.lastTo = VW.g.pos.undoStack(ply - 1).mv.toSq
    End If
End Sub

Private Sub ResetViewer()
    VW.autoPlay = False
    VW.speed = 1
    VW.flipped = False
    VW.listScroll = 0
    VW.ply = 0
    VW.sawEnd = False
    SetPly(0, False)
End Sub

Sub Viewer_Start(ByVal index As Integer)
    VW.index = index
    VW.returnTo = SCREEN_FAMOUS
    VW.errorText = ""
    Dim As FamousGame Ptr fg = Famous_Get(index)
    Dim As PgnTags tags
    If fg = 0 OrElse Not Pgn_ParseGame(fg->pgn, VW.g, tags, VW.errorText) Then
        Game_New(VW.g)
    End If
    ResetViewer()
End Sub

'' Replays any PGN game (imported file, tournament games) in the viewer.
Function Viewer_StartPgn(ByRef gameText As Const String, ByVal returnScreen As Integer, _
                         ByRef errMsg As String) As Boolean
    Static tmp As ChessGame
    Dim As PgnTags tags
    If Not Pgn_ParseGame(gameText, tmp, tags, errMsg) Then Return False
    VW.g = tmp
    VW.index = -1
    VW.returnTo = returnScreen
    VW.errorText = ""
    With VW.ext
        .white = Pgn_GetTag(tags, "White", "?")
        .black = Pgn_GetTag(tags, "Black", "?")
        .event = Pgn_GetTag(tags, "Event", "")
        .site = Pgn_GetTag(tags, "Site", "")
        .dateStr = Pgn_GetTag(tags, "Date", "")
        .year = ValInt(Left(.dateStr, 4))
        .result = Pgn_GetTag(tags, "Result", "*")
        .eco = Pgn_GetTag(tags, "ECO", "")
        .opening = Pgn_GetTag(tags, "Opening", "")
        .intro = ""
        .source = "file"
        .plies = tmp.moveCount
        .pgn = gameText
    End With
    ResetViewer()
    Return True
End Function

'' "12. Nf3" or "12... Nf6" for ply index i (0-based).
Private Function MoveLabel(ByVal i As Integer) As String
    '' Move number and side of the first move
    Dim As Position tmp
    Dim As String e
    Pos_LoadFEN(tmp, VW.g.startFEN, e)
    Dim As Integer side = tmp.sideToMove, num = tmp.fullmoveNumber, k
    For k = 1 To i
        If side = SIDE_BLACK Then num += 1
        side Xor= 1
    Next
    Return num & IIf(side = SIDE_WHITE, ". ", "... ") & VW.g.sanMoves(i)
End Function

Function Viewer_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_VIEWER
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    Dim As FamousGame Ptr fg = IIf(VW.index < 0, @VW.ext, Famous_Get(VW.index))
    If fg = 0 Then Return SCREEN_FAMOUS
    UI_DrawBackground()
    Screen_DrawHeader(IIf(VW.index < 0, "Replay game", "Famous Games"))

    '' Auto play
    Dim As Double delays(0 To 2) = {2.6, 1.5, 0.7}
    If VW.autoPlay AndAlso CBool(Timer >= VW.nextAt) AndAlso Not BC_Busy(ViewBC) Then
        If VW.ply < VW.g.moveCount Then
            SetPly(VW.ply + 1, True)
            '' Give the reader more time on moves with a comment.
            VW.nextAt = Timer + delays(VW.speed) + IIf(VW.g.comments(VW.ply - 1) <> "", 2.0, 0)
        Else
            VW.autoPlay = False
        End If
    End If

    '' Board
    ViewBoard.theme = AppConfig.boardTheme
    ViewBoard.pieceSet = AppConfig.pieceSet
    ViewBoard.showCoords = AppConfig.showCoordinates
    ViewBoard.flipped = VW.flipped
    Board_Layout(ViewBoard, 0, 0, 10)
    Dim As Integer panelMin = 400
    Dim As Integer sq = (sh - 74 - 2 * ViewBoard.margin) \ 8
    If sq * 8 + 2 * ViewBoard.margin > sw - panelMin - 48 Then sq = (sw - panelMin - 48 - 2 * ViewBoard.margin) \ 8
    Board_Layout(ViewBoard, 0, 0, sq)
    Dim As Integer outer = Board_OuterSize(ViewBoard)
    Board_Layout(ViewBoard, 16, 50 + (sh - 50 - outer) \ 2, sq)
    Dim As BoardMarks extra
    Board_ClearMarks(extra)
    Dim As ChessMove dummy
    Dim As String illegal
    BC_Frame(ViewBC, ViewBoard, VW.pos, False, extra, dummy, illegal)

    '' Panel
    Dim As Integer px = 16 + outer + 20, pw = sw - px - 16, y = 62
    Gfx_Panel(px, y, pw, sh - y - 16, 14, RGB(252, 249, 240), RGB(150, 120, 80))
    Dim As Integer tx = px + 16, tw = pw - 32
    Dim As String title = fg->white & " - " & fg->black
    Dim As Integer ts = 24
    Do While ts > 14 AndAlso Text_Width(title, ts) > tw
        ts -= 1
    Loop
    Text_Draw(tx, y + 12, title, ts, RGB(80, 52, 24))
    Dim As String info = fg->event & IIf(fg->year > 0, " " & fg->year, "") & "   " & fg->result
    Text_Draw(tx, y + 44, Left(info, tw \ 8), 16, RGB(120, 100, 80))
    If fg->opening <> "" Then Text_Draw(tx, y + 64, Left(fg->eco & " " & fg->opening, tw \ 8), 16, RGB(52, 100, 170))

    '' Current move and its comment
    Dim As Integer cy = y + 92, ch = 150
    Gfx_Panel(tx - 6, cy, tw + 12, ch, 10, RGB(255, 250, 220), RGB(200, 170, 80), False)
    Dim As String moveText, comment
    If VW.ply = 0 Then
        moveText = "Start of the game"
        comment = IIf(fg->intro <> "", fg->intro, "Press 'Next' or 'Play' to replay the game.")
    Else
        moveText = MoveLabel(VW.ply - 1)
        comment = VW.g.comments(VW.ply - 1)
        If comment = "" AndAlso VW.ply = VW.g.moveCount Then comment = "The game ended: " & Game_StatusText(VW.g)
    End If
    If VW.errorText <> "" Then comment = "This game could not be read: " & VW.errorText
    Text_Draw(tx + 4, cy + 8, moveText, 24, RGB(80, 52, 24))
    If comment <> "" Then
        Dim As Integer cs = Text_FitSize(comment, tw - 8, ch - 50, 20, 13)
        Text_DrawWrapped(tx + 4, cy + 42, tw - 8, comment, cs, RGB(70, 56, 20))
    End If

    '' Move list (click a move to jump there)
    Dim As Integer btnTop = sh - 16 - 3 * 50
    Dim As Integer ly = cy + ch + 10, lh = btnTop - 10 - ly
    Gfx_Panel(tx - 6, ly, tw + 12, lh, 10, RGB(255, 255, 255), RGB(150, 130, 100), False)
    Dim As Integer rowH = 22, visible = (lh - 12) \ rowH
    Dim As Position startPos
    Dim As String e
    Pos_LoadFEN(startPos, VW.g.startFEN, e)
    Dim As Integer offset = IIf(startPos.sideToMove = SIDE_BLACK, 1, 0)
    Dim As Integer rows = (VW.g.moveCount + offset + 1) \ 2
    Dim As Integer curRow = (VW.ply - 1 + offset) \ 2
    If VW.ply > 0 Then
        If curRow < VW.listScroll Then VW.listScroll = curRow
        If curRow >= VW.listScroll + visible Then VW.listScroll = curRow - visible + 1
    End If
    If UI_Hover(tx, ly, tw, lh) AndAlso UI.wheelDelta <> 0 Then VW.listScroll -= UI.wheelDelta * 2
    If VW.listScroll > rows - visible Then VW.listScroll = rows - visible
    If VW.listScroll < 0 Then VW.listScroll = 0
    Dim As Integer r, c
    For r = VW.listScroll To VW.listScroll + visible - 1
        If r >= rows Then Exit For
        Dim As Integer ry = ly + 6 + (r - VW.listScroll) * rowH
        Text_Draw(tx + 4, ry + 3, (startPos.fullmoveNumber + r) & ".", 16, RGB(140, 120, 100))
        For c = 0 To 1
            Dim As Integer pl = r * 2 + c - offset
            If pl < 0 OrElse pl >= VW.g.moveCount Then Continue For
            Dim As Integer cx = tx + 56 + c * ((tw - 60) \ 2), cwid = (tw - 60) \ 2 - 6
            If pl = VW.ply - 1 Then Gfx_RoundRect(cx - 4, ry, cwid, rowH - 2, 5, RGB(255, 226, 120))
            Dim As ULong mc = IIf(VW.g.comments(pl) <> "", RGB(40, 90, 170), RGB(30, 30, 40))
            Text_Draw(cx, ry + 3, VW.g.sanMoves(pl), 16, mc)
            If UI_Hover(cx - 4, ry, cwid, rowH) Then
                If VW.g.comments(pl) <> "" Then UI_SetTooltip("vw.c" & pl, VW.g.comments(pl))
                If UI.pressed Then
                    VW.autoPlay = False
                    SetPly(pl + 1, False)
                End If
            End If
        Next
    Next

    '' Controls
    Dim As Integer bw5 = (tw - 4 * 8) \ 5, bh = 42, i
    Dim As String labels(0 To 4) = {"|<", "<", IIf(VW.autoPlay, "Pause", "Play"), ">", ">|"}
    Dim As String tips(0 To 4) = {"First position (Home)", "Previous move (Left arrow)", _
                                  "Play the game automatically (Space)", "Next move (Right arrow)", "Last position (End)"}
    For i = 0 To 4
        If UI_Button("vw.b" & i, tx + i * (bw5 + 8), btnTop, bw5, bh, labels(i), True, tips(i), _
                     IIf(i = 2, BTN_PRIMARY, BTN_NORMAL)) Then
            Select Case i
            Case 0 : VW.autoPlay = False : SetPly(0, False)
            Case 1 : VW.autoPlay = False : SetPly(VW.ply - 1, False)
            Case 2
                VW.autoPlay = Not VW.autoPlay
                If VW.autoPlay AndAlso VW.ply >= VW.g.moveCount Then SetPly(0, False)
                VW.nextAt = Timer + 0.4
            Case 3 : VW.autoPlay = False : SetPly(VW.ply + 1, True)
            Case 4 : VW.autoPlay = False : SetPly(VW.g.moveCount, False)
            End Select
        End If
    Next
    Dim As Integer bw2 = (tw - 16) \ 3
    UI_Selector("vw.speed", tx, btnTop + 50, bw2 * 2 + 8, bh, "Slow|Normal|Fast", VW.speed, True, "Speed of the automatic replay.")
    If UI_Button("vw.flip", tx + bw2 * 2 + 16, btnTop + 50, bw2, bh, "Flip", True, "Turn the board around (F).") Then
        VW.flipped = Not VW.flipped
    End If
    Dim As Boolean canPlay = (VW.ply < VW.g.moveCount) OrElse Not Game_IsOver(VW.g)
    Dim As Integer bw3 = (tw - 16) \ 3
    If UI_Button("vw.play", tx, btnTop + 100, bw3, bh, "Play here", canPlay, _
                 "Continue this game yourself against the computer, from the position on the board.") Then
        Dim As String errMsg
        If Play_StartFromGamePrefix(NewGameOpts, VW.g, VW.ply, errMsg) Then nextScreen = SCREEN_PLAY
    End If
    If UI_Button("vw.review", tx + bw3 + 8, btnTop + 100, bw3, bh, "Review", VW.g.moveCount > 0, _
                 "Let the computer rate every move of this game.") Then
        VW.autoPlay = False
        Review_Start(VW.g, SCREEN_VIEWER, VW.flipped)
        nextScreen = SCREEN_REVIEW
    End If
    Dim As Boolean goBack = UI_Button("vw.back", tx + 2 * (bw3 + 8), btnTop + 100, bw3, bh, _
                                      "Game list", True, "Choose another game (Esc).")

    '' Watching a game to its end counts for the "History Fan" achievement.
    If CBool(VW.ply = VW.g.moveCount) AndAlso CBool(VW.g.moveCount > 0) AndAlso CBool(VW.index >= 0) AndAlso Not VW.sawEnd Then
        VW.sawEnd = True
        Profile_Current()->famousWatched += 1
        Profile_Save()
        App_CheckAchievements()
    End If

    '' Keyboard
    Select Case UI.keyCode
    Case KEY_RIGHT : VW.autoPlay = False : SetPly(VW.ply + 1, True)
    Case KEY_LEFT : VW.autoPlay = False : SetPly(VW.ply - 1, False)
    Case 1071 : VW.autoPlay = False : SetPly(0, False)                 '' Home
    Case 1079 : VW.autoPlay = False : SetPly(VW.g.moveCount, False)    '' End
    Case Asc(" ") : VW.autoPlay = Not VW.autoPlay : VW.nextAt = Timer + 0.4
    Case Asc("f"), Asc("F") : VW.flipped = Not VW.flipped
    Case KEY_ESCAPE : goBack = True
    End Select
    If goBack Then
        VW.autoPlay = False
        nextScreen = VW.returnTo
    End If
    Return nextScreen
End Function

'' Screenshot helper
Sub Viewer_DebugShow(ByVal index As Integer, ByVal ply As Integer)
    Viewer_Start(index)
    SetPly(ply, False)
End Sub
