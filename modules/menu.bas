'' =====================================================================
'' BeginnerChess - menu.bas
'' Main menu, New Game, Options and About screens.
'' =====================================================================
#include once "screens.bi"

Dim Shared NewGameOpts As NewGameOptions
Dim Shared NGInput As InputDialogState
Dim Shared NGPractice As Boolean = False

Sub NewGame_SetPractice(ByVal practice As Boolean)
    NGPractice = practice
    If practice Then NewGameOpts.opponent = OPP_COMPUTER
End Sub
Dim Shared MenuDlg As DialogState
Dim Shared WelcomeInput As InputDialogState
Dim Shared WelcomeChecked As Boolean = False

'' Is there an unfinished game in the autosave slot? (checked once a second)
Private Function HaveAutosave() As Boolean
    Static lastCheck As Double = -10
    Static result As Boolean = False
    If Abs(Timer - lastCheck) > 1 Then
        Dim As SaveInfo info
        result = Save_ReadInfo(0, info) AndAlso info.valid AndAlso info.result = "*"
        lastCheck = Timer
    End If
    Return result
End Function

'' A small decorative board for the menu screens.
Dim Shared MenuBoard As BoardView
Dim Shared MenuPos As Position
Dim Shared MenuReady As Boolean = False

Private Sub EnsureMenuBoard()
    If MenuReady Then Exit Sub
    Dim As String errMsg
    '' The Italian Game after 1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5
    Pos_LoadFEN(MenuPos, "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4", errMsg)
    MenuBoard.showCoords = True
    MenuReady = True
End Sub

Sub Screen_DrawHeader(ByRef title As Const String)
    Dim As Integer sw = Gfx_Width()
    Gfx_GradientRect(0, 0, sw, 48, RGB(92, 60, 32), RGB(62, 38, 18))
    Gfx_FillRect(0, 48, sw, 2, RGB(196, 160, 100))
    Text_DrawShadow(16, 10, "Beginner Chess", 28, RGB(255, 236, 190), RGBA(0, 0, 0, 140))
    If title <> "" Then
        Text_Draw(sw - Text_Width(title, 22) - 18, 14, title, 22, RGB(240, 222, 186))
    End If
End Sub

'' ---------------------------------------------------------------------
'' Main menu
'' ---------------------------------------------------------------------
Function Menu_Frame() As Integer
    EnsureMenuBoard()
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    Dim As Integer nextScreen = SCREEN_MENU
    UI_DrawBackground()

    '' Title
    Const TITLE_TEXT = "BEGINNER CHESS"
    Text_DrawShadow((sw - Text_Width(TITLE_TEXT, 56)) \ 2, 30, TITLE_TEXT, 56, _
                    RGB(255, 226, 150), RGBA(0, 0, 0, 160))
    '' Subtitle "Learn • Practice • Play" (the bullets are drawn as dots).
    Dim As String words(0 To 2) = {"Learn", "Practice", "Play"}
    Dim As Integer gapW = 36, total = 2 * gapW, k
    For k = 0 To 2 : total += Text_Width(words(k), 24) : Next
    Dim As Integer tx = (sw - total) \ 2
    For k = 0 To 2
        Text_Draw(tx, 100, words(k), 24, RGB(214, 226, 240))
        tx += Text_Width(words(k), 24)
        If k < 2 Then
            Gfx_FillCircle(tx + gapW \ 2, 112, 3.5, RGB(255, 226, 150))
            tx += gapW
        End If
    Next

    '' Decorative board on the left
    '' As big as fits next to the 380-pixel-wide button column.
    Dim As Integer sq = (sh - 240) \ 8
    If sq > (sw - 50 - 60 - 380 - 40 - 50) \ 8 Then sq = (sw - 50 - 60 - 380 - 40 - 50) \ 8
    If sq > 90 Then sq = 90
    Board_Layout(MenuBoard, 50, 160, sq)
    Dim As BoardMarks mk
    Board_ClearMarks(mk)
    mk.lastFrom = Sq_Parse("f8") : mk.lastTo = Sq_Parse("c5")
    Board_Draw(MenuBoard, MenuPos, mk)

    '' Menu buttons on the right
    Dim As Integer bx = 50 + Board_OuterSize(MenuBoard) + 60
    Dim As Integer bw = sw - bx - 50, bh = 44, gap = 8
    Dim As Integer by = 150
    '' First start: greet the new player and ask for a name (only once).
    If Not WelcomeChecked Then
        WelcomeChecked = True
        If Profile_GetValue("welcomed") = "" AndAlso Not UI.fakeInput Then
            InputDialog_Open(WelcomeInput, "welcome", "Welcome to Beginner Chess!", _
                             "Hello! What is your name? (You can change it later in Player Profile.)", "", "OK|Skip", 24)
        End If
    End If
    If WelcomeInput.active Then UI.blockInput = True
    Dim As Boolean showContinue = HaveAutosave()
    If showContinue Then
        bh = 40 : gap = 6 : by = 140
        UI.blockInput = MenuDlg.active
    End If
    '' 12 buttons (13 with "Continue Game"): make them fit the window height.
    Dim As Integer nRows = 12 + IIf(showContinue, 1, 0)
    Dim As Integer rowStep = (sh - by - 34) \ nRows      '' room for the player line at the bottom
    If rowStep < bh + gap Then
        gap = 6
        bh = rowStep - gap
    End If
    If bw > 380 Then bx += (bw - 380) \ 2 : bw = 380
    Dim As Integer i = 0
    #define ROWY(n) (by + (n) * (bh + gap))
    If showContinue Then
        If UI_Button("menu.continue", bx, by, bw, bh, "Continue Game", True, _
                     "Go back to the game you were playing.", BTN_PRIMARY) Then
            Dim As String errMsg
            If Play_LoadFromSlot(0, errMsg) Then
                nextScreen = SCREEN_PLAY
            Else
                Dialog_Open(MenuDlg, "err", "Could not continue", errMsg, "OK")
            End If
        End If
        by += bh + gap
    End If

    If UI_Button("menu.play", bx, ROWY(0), bw, bh, "Play Chess", True, _
                 "Start a new game.", BTN_MENU) Then
        NewGame_SetPractice(False)
        nextScreen = SCREEN_NEWGAME
    End If
    If UI_Button("menu.online", bx, ROWY(1), bw, bh, "Play Online", True, _
                 "Play against people on the Internet - free, as a guest or with an account. (Needs an Internet connection.)", BTN_MENU) Then
        Online_Enter()
        nextScreen = SCREEN_ONLINE
    End If
    If UI_Button("menu.practice", bx, ROWY(2), bw, bh, "Practice", True, _
                 "Relaxed games with hints, threats, take-backs and explanations of mistakes.", BTN_MENU) Then
        NewGame_SetPractice(True)
        nextScreen = SCREEN_NEWGAME
    End If
    If UI_Button("menu.tournament", bx, ROWY(3), bw, bh, "Tournament", True, _
                 "Career ladder and tournaments against computer opponents.", BTN_MENU) Then nextScreen = SCREEN_TOURNAMENT
    If UI_Button("menu.learn", bx, ROWY(4), bw, bh, "Learn Chess", True, _
                 "Step-by-step lessons: the rules, tactics, strategy, endgames and the history of chess styles.", _
                 BTN_MENU) Then nextScreen = SCREEN_LESSONS
    If UI_Button("menu.puzzles", bx, ROWY(5), bw, bh, "Chess Puzzles", True, _
                 "Mate in one and two, forks, pins, skewers, endgames and more.", BTN_MENU) Then nextScreen = SCREEN_PUZZLES
    If UI_Button("menu.famous", bx, ROWY(6), bw, bh, "Famous Games", True, _
                 "Replay great games from chess history, move by move.", BTN_MENU) Then nextScreen = SCREEN_FAMOUS
    If UI_Button("menu.analyze", bx, ROWY(7), bw, bh, "Analyze Position", True, _
                 "Set up any position and let the computer explain it.", BTN_MENU) Then
        Analyze_Start(START_FEN, SCREEN_MENU)
        nextScreen = SCREEN_ANALYZE
    End If
    If UI_Button("menu.profile", bx, ROWY(8), bw, bh, "Player Profile", True, _
                 "Your statistics, rating and achievements - and who is playing.", BTN_MENU) Then nextScreen = SCREEN_PROFILE
    If UI_Button("menu.options", bx, ROWY(9), bw, bh, "Options", True, _
                 "Board colours, move hints and animation.", BTN_MENU) Then nextScreen = SCREEN_OPTIONS
    If UI_Button("menu.about", bx, ROWY(10), bw, bh, "About", True, _
                 "About Beginner Chess.", BTN_MENU) Then nextScreen = SCREEN_ABOUT
    If UI_Button("menu.exit", bx, ROWY(11), bw, bh, "Exit", True, _
                 "Close Beginner Chess.", BTN_MENU) Then nextScreen = SCREEN_QUIT
    #undef ROWY

    Text_Draw(12, sh - 22, "Version " & CM_VERSION, 16, RGB(150, 170, 196))
    Dim As String who = "Player: " & Profile_Current()->name & "  (rating " & Profile_Current()->rating & ")"
    Text_Draw(sw - Text_Width(who, 18) - 16, sh - 26, who, 18, RGB(214, 226, 240))
    If WelcomeInput.active Then
        Dim As Integer r = InputDialog_Run(WelcomeInput)
        If r = 0 AndAlso Trim(WelcomeInput.text) <> "" Then Profile_Rename(WelcomeInput.text)
        If r = 0 OrElse r = 1 Then
            WelcomeInput.active = False
            Profile_SetValue("welcomed", "1")
            Profile_Save()
            If r = 0 AndAlso Trim(WelcomeInput.text) <> "" Then UI_ShowToast("Welcome,", Trim(WelcomeInput.text) & "!")
        End If
    ElseIf MenuDlg.active Then
        Dialog_Run(MenuDlg)
    ElseIf UI.keyCode = KEY_ESCAPE Then
        nextScreen = SCREEN_QUIT
    End If
    Return nextScreen
End Function

'' ---------------------------------------------------------------------
'' New game
'' ---------------------------------------------------------------------
Function NewGame_Frame() As Integer
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    Dim As Integer nextScreen = SCREEN_NEWGAME
    UI.blockInput = NGInput.active
    UI_DrawBackground()
    Screen_DrawHeader(IIf(NGPractice, "Practice", "New Game"))
    If NGPractice Then NewGameOpts.opponent = OPP_COMPUTER

    Dim As Integer pw = 640, ph = 500
    Dim As Integer px = (sw - pw) \ 2, py = 74
    Gfx_Panel(px, py, pw, ph, 18, RGB(250, 246, 236), RGB(120, 90, 56))
    Text_DrawCentered(sw \ 2, py + 22, IIf(NGPractice, "Set up a practice game", "Set up your game"), 34, RGB(80, 52, 24))

    Dim As Integer lx = px + 40, sx = px + 250, sw2 = pw - 290, rowH = 54, ry = py + 90
    Dim As Integer txtC = RGB(50, 44, 36)
    Dim As Boolean vsComputer = (NewGameOpts.opponent = OPP_COMPUTER)

    Text_Draw(lx, ry + 10, "Opponent:", 24, txtC)
    UI_Selector("ng.opp", sx, ry, sw2, 44, "Human (2 players)|Computer", NewGameOpts.opponent, Not NGPractice, _
                "Play against a friend on this computer, or against the computer.")
    ry += rowH
    Text_Draw(lx, ry + 10, "Play as:", 24, txtC)
    UI_Selector("ng.side", sx, ry, sw2, 44, "White|Black|Random", NewGameOpts.playAs, True, _
                "Which colour you play. That side is shown at the bottom of the board.")
    ry += rowH
    Dim As String levels = "", styles = ""
    Dim As Integer k
    For k = 0 To LEVEL_COUNT - 1
        levels &= IIf(k > 0, "|", "") & Engine_LevelName(k)
    Next
    For k = 0 To STYLE_COUNT - 1
        styles &= IIf(k > 0, "|", "") & Engine_StyleName(k)
    Next
    Text_Draw(lx, ry + 10, "Difficulty:", 24, IIf(vsComputer, txtC, RGB(150, 150, 150)))
    UI_Selector("ng.diff", sx, ry, sw2, 44, levels, NewGameOpts.difficulty, vsComputer, _
                "How strong the computer plays. " & Engine_LevelDescription(NewGameOpts.difficulty))
    ry += rowH
    Text_Draw(lx, ry + 10, "Style:", 24, IIf(vsComputer, txtC, RGB(150, 150, 150)))
    UI_Selector("ng.style", sx, ry, sw2, 44, styles, NewGameOpts.style, vsComputer, _
                "The computer's playing personality. " & Engine_StyleDescription(NewGameOpts.style))
    ry += rowH + 10

    Dim As Boolean canStart = True
    If NGPractice Then
        Text_DrawWrapped(px + 40, ry, pw - 80, "Practice: hints, threats, take-backs, and the coach " & _
            "explains your mistakes. Practice games do not change your rating.", 20, RGB(60, 80, 120), True)
    ElseIf vsComputer Then
        Text_DrawWrapped(px + 40, ry, pw - 80, Engine_LevelName(NewGameOpts.difficulty) & ": " & _
            Engine_LevelDescription(NewGameOpts.difficulty) & "|" & Engine_StyleName(NewGameOpts.style) & ": " & _
            Engine_StyleDescription(NewGameOpts.style), 20, RGB(60, 80, 120), True)
    Else
        Text_DrawWrapped(px + 40, ry, pw - 80, _
            "Two players take turns at this computer. White always moves first.", 20, RGB(70, 90, 70), True)
    End If

    Dim As Integer bw = 240, bh = 60
    Dim As Boolean startClicked = UI_Button("ng.start", (sw - bw) \ 2, py + ph - bh - 30, bw, bh, "START GAME", canStart, _
                 "Begin the game!", BTN_PRIMARY)
    If canStart AndAlso UI.keyCode = KEY_ENTER Then startClicked = True
    If startClicked AndAlso Not NGInput.active Then
        AppConfig.newOpponent = NewGameOpts.opponent
        AppConfig.newPlayAs = NewGameOpts.playAs
        AppConfig.newDifficulty = NewGameOpts.difficulty
        AppConfig.newStyle = NewGameOpts.style
        Settings_Save(AppConfig, Settings_FileName())
        If NGPractice Then Play_StartPractice(NewGameOpts) Else Play_Start(NewGameOpts)
        nextScreen = SCREEN_PLAY
    End If

    '' Other ways to start: saved game, PGN file, FEN position.
    Dim As Integer obw = 200, obh = 46, ogap = 20
    Dim As Integer ox = (sw - 3 * obw - 2 * ogap) \ 2, oy = py + ph + 18
    If UI_Button("ng.load", ox, oy, obw, obh, "Load Saved Game", True, _
                 "Continue a game you saved earlier.") Then
        SaveLoad_Begin(SLMODE_LOAD, SCREEN_NEWGAME)
        nextScreen = SCREEN_SAVELOAD
    End If
    If UI_Button("ng.import", ox + obw + ogap, oy, obw, obh, "Import PGN", True, _
                 "Open a game from a PGN file. The settings above (opponent, side, level) are used " & _
                 "if you continue playing it.") Then
        Import_Begin(SCREEN_NEWGAME)
        nextScreen = SCREEN_IMPORT
    End If
    If UI_Button("ng.fen", ox + 2 * (obw + ogap), oy, obw, obh, "From Position", True, _
                 "Start from any position written in FEN notation, with the settings above.") Then
        InputDialog_Open(NGInput, "fen", "Start from a position", _
                         "Type or paste a position in FEN notation, for example: " & _
                         "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", "", "Start|Paste|Cancel", 100)
    End If

    Dim As Boolean goBack = UI_Button("ng.back", 20, sh - 64, 140, 46, "< Back", True, "Return to the main menu.")
    If UI.keyCode = KEY_ESCAPE AndAlso Not NGInput.active Then goBack = True
    If goBack Then nextScreen = SCREEN_MENU

    If NGInput.active Then
        Select Case InputDialog_Run(NGInput)
        Case 0
            Dim As String errMsg
            If Play_StartFromFEN(NewGameOpts, Trim(NGInput.text), errMsg) Then
                NGInput.active = False
                nextScreen = SCREEN_PLAY
            Else
                NGInput.errorText = "That position cannot be used: " & errMsg
            End If
        Case 1
            InputDialog_Paste(NGInput)
        Case 2
            NGInput.active = False
        End Select
    End If
    Return nextScreen
End Function

'' ---------------------------------------------------------------------
'' Options
'' ---------------------------------------------------------------------
'' Window sizes that fit on this desktop.
Private Function WindowSizeList(ws() As Integer, hs() As Integer) As Integer
    Dim As Integer dw, dh
    Gfx_DesktopSize(dw, dh)
    Dim As Integer cw(0 To 6) = {1024, 1152, 1280, 1400, 1600, 1920, 2048}
    Dim As Integer ch(0 To 6) = {768, 864, 960, 1050, 1200, 1440, 1536}
    Dim As Integer i, n = 0, haveCurrent = 0
    For i = 0 To 6
        If i = 0 OrElse (cw(i) <= dw AndAlso ch(i) <= dh - 40) Then
            ws(n) = cw(i) : hs(n) = ch(i)
            If cw(i) = AppConfig.screenW AndAlso ch(i) = AppConfig.screenH Then haveCurrent = 1
            n += 1
        End If
    Next
    If haveCurrent = 0 Then ws(n) = AppConfig.screenW : hs(n) = AppConfig.screenH : n += 1
    Return n
End Function

Private Function OnOff(ByVal b As Boolean) As Integer
    Return IIf(b, 0, 1)
End Function

Function Options_Frame() As Integer
    EnsureMenuBoard()
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    Dim As Integer nextScreen = SCREEN_OPTIONS
    UI_DrawBackground()
    Screen_DrawHeader("Options")

    Dim As Integer ty = 62, ph = sh - ty - 82
    Dim As Integer lw = (sw - 72) \ 2, lx = 24, rx = lx + lw + 24
    Dim As ULong txtC = RGB(50, 44, 36), headC = RGB(80, 52, 24)
    Dim As Integer rowH = 52, selH = 42, v

    '' ---- Left: board and pieces ----
    Gfx_Panel(lx, ty, lw, ph, 16, RGB(250, 246, 236), RGB(120, 90, 56))
    Text_Draw(lx + 20, ty + 14, "Board and pieces", 28, headC)
    Dim As Integer sx = lx + lw * 44 \ 100, selW = lw - (sx - lx) - 18, y = ty + 58

    Text_Draw(lx + 20, y + 10, "Board theme:", 20, txtC)
    Dim As String themes = ""
    Dim As Integer t
    For t = 0 To THEME_COUNT - 1
        themes &= IIf(t > 0, "|", "") & Board_ThemeName(t)
    Next
    UI_Selector("opt.theme", sx, y, selW, selH, themes, AppConfig.boardTheme, True, "Colours of the chess board.")
    y += rowH
    Text_Draw(lx + 20, y + 10, "Piece set:", 20, txtC)
    UI_Selector("opt.pieces", sx, y, selW, selH, Pieces_SetName(0) & "|" & Pieces_SetName(1), AppConfig.pieceSet, True, _
                "Classic: traditional pieces. Bold: thick outlines that are easier to see.")
    y += rowH
    v = OnOff(AppConfig.showLegalMoves)
    Text_Draw(lx + 20, y + 10, "Show moves:", 20, txtC)
    If UI_Selector("opt.legal", sx, y, selW, selH, "On|Off", v, True, _
                   "Show dots on the squares the selected piece can move to.") Then AppConfig.showLegalMoves = (v = 0)
    y += rowH
    v = OnOff(AppConfig.showCoordinates)
    Text_Draw(lx + 20, y + 10, "Coordinates:", 20, txtC)
    If UI_Selector("opt.coords", sx, y, selW, selH, "On|Off", v, True, _
                   "Show the letters a-h and numbers 1-8 around the board.") Then AppConfig.showCoordinates = (v = 0)
    y += rowH
    Select Case AppConfig.animationMs
    Case 0 : v = 0
    Case Is <= 120 : v = 1
    Case Is <= 200 : v = 2
    Case Else : v = 3
    End Select
    Text_Draw(lx + 20, y + 10, "Animation:", 20, txtC)
    If UI_Selector("opt.anim", sx, y, selW, selH, "Off|Fast|Normal|Slow", v, True, _
                   "How quickly pieces slide across the board.") Then
        Dim As Integer speeds(0 To 3) = {0, 110, 180, 320}
        AppConfig.animationMs = speeds(v)
    End If
    y += rowH
    v = OnOff(AppConfig.beginnerHints)
    Text_Draw(lx + 20, y + 10, "Beginner help:", 20, txtC)
    If UI_Selector("opt.hints", sx, y, selW, selH, "On|Off", v, True, _
                   "Friendly tips explaining the pieces and the rules while you play.") Then AppConfig.beginnerHints = (v = 0)
    y += rowH
    v = OnOff(AppConfig.achievementsOn)
    Text_Draw(lx + 20, y + 10, "Achievements:", 20, txtC)
    If UI_Selector("opt.ach", sx, y, selW, selH, "On|Off", v, True, _
                   "Show achievements and their pop-up messages.") Then AppConfig.achievementsOn = (v = 0)
    y += rowH + 4

    '' Live preview
    MenuBoard.theme = AppConfig.boardTheme
    MenuBoard.pieceSet = AppConfig.pieceSet
    MenuBoard.showCoords = AppConfig.showCoordinates
    Dim As Integer avail = ty + ph - 12 - y
    Board_Layout(MenuBoard, 0, 0, 10)
    Dim As Integer sq = (avail - 2 * MenuBoard.margin) \ 8
    If sq > (lw - 40) \ 8 Then sq = (lw - 40) \ 8
    If sq >= 12 Then
        Board_Layout(MenuBoard, 0, 0, sq)
        Board_Layout(MenuBoard, lx + (lw - Board_OuterSize(MenuBoard)) \ 2, y, sq)
        Dim As BoardMarks mk
        Board_ClearMarks(mk)
        mk.lastFrom = Sq_Parse("f8") : mk.lastTo = Sq_Parse("c5")
        If AppConfig.showLegalMoves Then
            mk.selectedSq = Sq_Parse("f3")
            mk.targets(Sq_Parse("g5")) = 1 : mk.targets(Sq_Parse("h4")) = 1 : mk.targets(Sq_Parse("d4")) = 1
            mk.targets(Sq_Parse("g1")) = 1 : mk.targets(Sq_Parse("e5")) = 2
        End If
        Board_Draw(MenuBoard, MenuPos, mk)
    End If

    '' ---- Right: sound and screen ----
    Gfx_Panel(rx, ty, lw, ph, 16, RGB(250, 246, 236), RGB(120, 90, 56))
    Text_Draw(rx + 20, ty + 14, "Sound and screen", 28, headC)
    sx = rx + lw * 44 \ 100
    y = ty + 58
    Dim As Boolean audioOk = Audio_Available()

    v = OnOff(AppConfig.soundOn)
    Text_Draw(rx + 20, y + 10, "Sound effects:", 20, IIf(audioOk, txtC, RGB(150, 150, 150)))
    If UI_Selector("opt.sound", sx, y, selW, selH, "On|Off", v, audioOk, "Sounds for moves, captures, check and more.") Then
        AppConfig.soundOn = (v = 0)
        Audio_SetSound(AppConfig.soundOn, AppConfig.soundVolume)
        Audio_Play(SND_MOVE)
    End If
    y += rowH
    Text_Draw(rx + 20, y + 10, "Effects volume:", 20, IIf(audioOk, txtC, RGB(150, 150, 150)))
    If UI_Slider("opt.svol", sx, y, selW - 60, selH, AppConfig.soundVolume, 0, 100, audioOk AndAlso AppConfig.soundOn, _
                 "Loudness of the sound effects.") Then Audio_SetSound(AppConfig.soundOn, AppConfig.soundVolume)
    If UI.released AndAlso UI_Hover(sx, y, selW - 60, selH) Then Audio_Play(SND_CAPTURE)
    Text_Draw(sx + selW - 52, y + 11, AppConfig.soundVolume & "%", 20, txtC)
    y += rowH
    v = OnOff(AppConfig.musicOn)
    Text_Draw(rx + 20, y + 10, "Music:", 20, IIf(audioOk, txtC, RGB(150, 150, 150)))
    If UI_Selector("opt.music", sx, y, selW, selH, "On|Off", v, audioOk, _
                   "Calm background music (the program's own, or your files in sound/music).") Then
        AppConfig.musicOn = (v = 0)
        Audio_SetMusic(AppConfig.musicOn, AppConfig.musicVolume)
    End If
    y += rowH
    Text_Draw(rx + 20, y + 10, "Music volume:", 20, IIf(audioOk, txtC, RGB(150, 150, 150)))
    If UI_Slider("opt.mvol", sx, y, selW - 60, selH, AppConfig.musicVolume, 0, 100, audioOk AndAlso AppConfig.musicOn, _
                 "Loudness of the music.") Then Audio_SetMusic(AppConfig.musicOn, AppConfig.musicVolume)
    Text_Draw(sx + selW - 52, y + 11, AppConfig.musicVolume & "%", 20, txtC)
    y += rowH

    Dim As Integer ws(0 To 9), hs(0 To 9)
    Dim As Integer nSizes = WindowSizeList(ws(), hs()), i, cur = 0
    Dim As String sizeOpts = ""
    For i = 0 To nSizes - 1
        sizeOpts &= IIf(i > 0, "|", "") & ws(i) & " x " & hs(i)
        If ws(i) = AppConfig.screenW AndAlso hs(i) = AppConfig.screenH Then cur = i
    Next
    Text_Draw(rx + 20, y + 10, "Window size:", 20, txtC)
    If UI_Selector("opt.size", sx, y, selW, selH, sizeOpts, cur, True, _
                   "Size of the Beginner Chess window. Bigger windows give a bigger board.") Then
        AppConfig.screenW = ws(cur)
        AppConfig.screenH = hs(cur)
    End If
    y += rowH
    v = OnOff(AppConfig.fullscreen)
    Text_Draw(rx + 20, y + 10, "Full screen:", 20, txtC)
    If UI_Selector("opt.full", sx, y, selW, selH, "On|Off", v, True, _
                   "Use the whole screen. If your computer refuses, Beginner Chess stays in a window.") Then
        AppConfig.fullscreen = (v = 0)
    End If
    y += rowH + 8

    If UI_Button("opt.test", rx + 20, y, 180, 40, "Test sound", audioOk, "Play a little fanfare.") Then
        Audio_Play(SND_VICTORY)
    End If
    y += 52
    Text_DrawWrapped(rx + 20, y, lw - 40, Audio_StatusText(), 16, IIf(audioOk, RGB(40, 110, 50), RGB(170, 70, 30)))
    y += 44
    Text_DrawWrapped(rx + 20, y, lw - 40, "Settings are saved in " & Settings_FileName(), 16, RGB(120, 110, 100))

    Dim As Boolean goBack = UI_Button("opt.back", 20, sh - 64, 140, 46, "< Back", True, _
                                      "Save the settings and return to the main menu.")
    If UI.keyCode = KEY_ESCAPE Then goBack = True
    If goBack Then
        Settings_Save(AppConfig, Settings_FileName())
        MenuBoard.theme = THEME_CLASSIC
        MenuBoard.pieceSet = PIECESET_CLASSIC
        MenuBoard.showCoords = True
        nextScreen = SCREEN_MENU
    End If
    Return nextScreen
End Function

'' ---------------------------------------------------------------------
'' About
'' ---------------------------------------------------------------------
Function About_Frame() As Integer
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    Dim As Integer nextScreen = SCREEN_ABOUT
    UI_DrawBackground()
    Screen_DrawHeader("About")

    Dim As Integer pw = 760, ph = 630
    Dim As Integer px = (sw - pw) \ 2, py = 66
    Gfx_Panel(px, py, pw, ph, 18, RGB(250, 246, 236), RGB(120, 90, 56))
    Text_DrawCentered(sw \ 2, py + 24, "Beginner Chess " & CM_VERSION, 40, RGB(80, 52, 24))
    Dim As Integer y = py + 90
    y += Text_DrawWrapped(px + 40, y, pw - 80, _
        "Beginner Chess is a chess game and chess school for children, beginners and " & _
        "intermediate players. Learn the rules, practise, solve puzzles, study famous " & _
        "games and play against the computer or against people on the Internet.", 22, RGB(40, 36, 30)) + 14
    y += Text_DrawWrapped(px + 40, y, pw - 80, _
        "Written in FreeBASIC. Runs on Linux (64-bit) and Windows (32-bit). The chess pieces " & _
        "and boards are original artwork drawn by the program itself.", 20, RGB(70, 64, 56)) + 14
    y += Text_DrawWrapped(px + 40, y, pw - 80, _
        "Copyright (c) 2026 Ronen Blumberg. Released under the MIT License (see LICENSE.txt).", _
        20, RGB(70, 64, 56)) + 14
    y += Text_DrawWrapped(px + 40, y, pw - 80, _
        "Keyboard: F = flip board, U or Backspace = take back a move, Esc = back / menu.", _
        20, RGB(70, 64, 56)) + 14
    y += Text_DrawWrapped(px + 40, y, pw - 80, _
        "Sound: all sounds and music are created by Beginner Chess itself and played with the BASS " & _
        "audio library (www.un4seen.com), when it is installed. " & Audio_StatusText(), 18, RGB(70, 64, 56)) + 12
    y += Text_DrawWrapped(px + 40, y, pw - 80, _
        "Famous Games library: SQLite 3 (public domain, www.sqlite.org), when it is installed.", 18, RGB(70, 64, 56)) + 12
    Text_DrawWrapped(px + 40, y, pw - 80, _
        "Online play: free and encrypted (server freedomnet.tech), using libcurl (curl.se) " & _
        "on Linux and WinHTTP on Windows.", 18, RGB(70, 64, 56))

    If UI_Button("about.back", 20, sh - 64, 140, 46, "< Back", True, "Return to the main menu.") _
       OrElse UI.keyCode = KEY_ESCAPE OrElse UI.keyCode = KEY_ENTER Then nextScreen = SCREEN_MENU
    Return nextScreen
End Function

Sub Menu_DebugOpenFenDialog(ByRef text As Const String)
    InputDialog_Open(NGInput, "fen", "Start from a position", _
                     "Type or paste a position in FEN notation, for example: " & _
                     "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", text, "Start|Paste|Cancel", 100)
End Sub
