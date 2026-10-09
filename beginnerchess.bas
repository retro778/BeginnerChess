'' =====================================================================
'' BeginnerChess - beginnerchess.bas
'' Main program: opens the window and runs the screen loop.
''
'' Command line:
''   beginnerchess                     normal start
''   beginnerchess --screenshots DIR   render each screen headlessly into
''                                     DIR/*.bmp and exit (for testing and
''                                     documentation)
'' =====================================================================
#include once "modules/screens.bi"
#include once "modules/online.bi"
#include once "dir.bi"
#include once "modules/lessons.bi"
#include once "modules/puzzles.bi"
#include once "modules/progress.bi"
#include once "modules/famous.bi"
#include once "modules/profile.bi"

Declare Sub RunScreenshots(ByRef outDir As Const String)

Randomize Timer
Settings_Defaults(AppConfig)
Dim Shared CurrentFullscreen As Boolean = False

'' Lessons and puzzles (missing files only make those sections empty).
Scope
    Dim As String contentErrors
    Lessons_LoadFolder(ExePath() & "/data/lessons", contentErrors)
    Puzzles_LoadFolder(ExePath() & "/data/puzzles", contentErrors)
End Scope

'' Opening book (optional: the computer simply plays without it).
Scope
    Dim As Integer badLines
    Dim As String bookErr
    Book_Load(ExePath() & "/data/openings/book.txt", badLines, bookErr)
End Scope

If Command(1) = "--screenshots" Then
    Dim As String outDir = Command(2)
    If outDir = "" Then outDir = "."
    '' Optional size, e.g. --screenshots /tmp/shots 1280x960
    Dim As String sizeArg = Command(3)
    If InStr(sizeArg, "x") > 0 Then
        AppConfig.screenW = ValInt(Left(sizeArg, InStr(sizeArg, "x") - 1))
        AppConfig.screenH = ValInt(Mid(sizeArg, InStr(sizeArg, "x") + 1))
        Settings_Validate(AppConfig)
    End If
    If Not Gfx_Open(AppConfig.screenW, AppConfig.screenH, False, True, "Beginner Chess") Then
        Print "Could not create the off-screen graphics buffer."
        End 1
    End If
    RunScreenshots(outDir)
    Engine_Shutdown()
    End 0
End If

'' Settings and the folder for saved games.
Settings_Load(AppConfig, Settings_ReadFileName())   '' also reads chessmaster.ini of the former name
Save_SetDirectory(Settings_DataDir() & "/saves")
'' Player profiles (each has its own statistics and lesson/puzzle progress).
Profile_Init(Settings_DataDir(), AppConfig.activeProfile)
AppConfig.activeProfile = Profile_Current()->id

'' Famous games library (SQLite; falls back to the PGN file without it).
If Dir(Settings_DataDir() & "/data", fbDirectory) = "" Then MkDir Settings_DataDir() & "/data"
Settings_MigrateFile(Settings_DataDir() & "/data/chessmaster.db", Settings_DataDir() & "/data/beginnerchess.db")
Famous_Init(Settings_DataDir() & "/data/beginnerchess.db", ExePath() & "/data/games/famous.pgn", _
            ExePath() & "/data/openings/book.txt")
NewGameOpts.opponent = AppConfig.newOpponent
NewGameOpts.playAs = AppConfig.newPlayAs
NewGameOpts.difficulty = AppConfig.newDifficulty
NewGameOpts.style = AppConfig.newStyle

'' Do not open a window larger than the desktop.
Scope
    Dim As Integer dw, dh
    Gfx_DesktopSize(dw, dh)
    Dim As Boolean tooBig = (AppConfig.screenW > dw) OrElse (AppConfig.screenH > dh)
    If tooBig AndAlso Not AppConfig.fullscreen Then
        AppConfig.screenW = 1024 : AppConfig.screenH = 768
    End If
End Scope
If Not Gfx_Open(AppConfig.screenW, AppConfig.screenH, AppConfig.fullscreen, False, "Beginner Chess") Then
    AppConfig.screenW = 1024 : AppConfig.screenH = 768 : AppConfig.fullscreen = False
    If Not Gfx_Open(1024, 768, False, False, "Beginner Chess") Then
        Print "Beginner Chess could not open a 1024x768 graphics window."
        Print "Please check that a graphical desktop is available."
        End 1
    End If
End If
CurrentFullscreen = AppConfig.fullscreen

'' Sound is optional: without BASS or a sound device the game is silent.
Audio_Init(ExePath())
Audio_SetSound(AppConfig.soundOn, AppConfig.soundVolume)
Audio_SetMusic(AppConfig.musicOn, AppConfig.musicVolume)

Dim As Integer currentScreen = SCREEN_MENU
Do
    UI_BeginFrame()
    Select Case currentScreen
    Case SCREEN_MENU    : currentScreen = Menu_Frame()
    Case SCREEN_NEWGAME : currentScreen = NewGame_Frame()
    Case SCREEN_PLAY    : currentScreen = Play_Frame()
    Case SCREEN_OPTIONS : currentScreen = Options_Frame()
    Case SCREEN_ABOUT   : currentScreen = About_Frame()
    Case SCREEN_SAVELOAD : currentScreen = SaveLoad_Frame()
    Case SCREEN_IMPORT  : currentScreen = Import_Frame()
    Case SCREEN_LESSONS : currentScreen = LessonList_Frame()
    Case SCREEN_LESSON  : currentScreen = LessonPlay_Frame()
    Case SCREEN_PUZZLES : currentScreen = PuzzleList_Frame()
    Case SCREEN_PUZZLE  : currentScreen = PuzzlePlay_Frame()
    Case SCREEN_FAMOUS  : currentScreen = FamousList_Frame()
    Case SCREEN_VIEWER  : currentScreen = Viewer_Frame()
    Case SCREEN_PROFILE : currentScreen = Profile_Frame()
    Case SCREEN_TOURNAMENT : currentScreen = Tournament_Frame()
    Case SCREEN_REVIEW  : currentScreen = Review_Frame()
    Case SCREEN_ANALYZE : currentScreen = Analyze_Frame()
    Case SCREEN_ONLINE  : currentScreen = Online_Frame()
    Case SCREEN_ONLINE_GAME : currentScreen = OnlineGame_Frame()
    Case SCREEN_ONLINE_PROFILE : currentScreen = OnlineProfile_Frame()
    Case SCREEN_ONLINE_LEADERBOARD : currentScreen = OnlineLeaderboard_Frame()
    End Select
    '' Online play: messages are handled on every screen (no-op when offline).
    currentScreen = OnlineUI_Pump(currentScreen)
    UI_EndFrame()
    Audio_Update()
    If UI.quitRequested Then currentScreen = SCREEN_QUIT

    '' Window size or full-screen changed in Options: reopen the window.
    Dim As Boolean displayChanged = (AppConfig.screenW <> Gfx_Width()) OrElse (AppConfig.screenH <> Gfx_Height())
    If AppConfig.fullscreen <> CurrentFullscreen Then displayChanged = True
    If displayChanged Then
        If Not Gfx_Open(AppConfig.screenW, AppConfig.screenH, AppConfig.fullscreen, False, "Beginner Chess") Then
            AppConfig.screenW = 1024 : AppConfig.screenH = 768 : AppConfig.fullscreen = False
            Gfx_Open(1024, 768, False, False, "Beginner Chess")
        End If
        CurrentFullscreen = AppConfig.fullscreen
    End If
Loop Until currentScreen = SCREEN_QUIT

Settings_Save(AppConfig, Settings_FileName())
Profile_Save()
Net_Shutdown()
Play_Shutdown()
Famous_Shutdown()
Engine_Shutdown()
Audio_Shutdown()
Text_Shutdown()
End 0

'' ---------------------------------------------------------------------
'' Automated screenshots
'' ---------------------------------------------------------------------
'' Print goes to the graphics window in graphics mode, so use the console.
Private Sub ConsoleLine(ByRef text As Const String)
    Dim As Integer f = FreeFile
    If Open Cons(For Output As #f) = 0 Then
        Print #f, text
        Close #f
    End If
End Sub

Private Sub Shot(ByRef outDir As Const String, ByRef fileName As Const String, ByVal screenId As Integer, _
                 ByVal mx As Integer = -1, ByVal my As Integer = -1)
    UI.mx = mx : UI.my = my
    '' Two frames so that hover tooltips appear.
    Dim As Integer i
    For i = 1 To 2
        UI_BeginFrame()
        Select Case screenId
        Case SCREEN_MENU    : Menu_Frame()
        Case SCREEN_NEWGAME : NewGame_Frame()
        Case SCREEN_PLAY    : Play_Frame()
        Case SCREEN_OPTIONS : Options_Frame()
        Case SCREEN_ABOUT   : About_Frame()
        Case SCREEN_SAVELOAD : SaveLoad_Frame()
        Case SCREEN_IMPORT  : Import_Frame()
        Case SCREEN_LESSONS : LessonList_Frame()
        Case SCREEN_LESSON  : LessonPlay_Frame()
        Case SCREEN_PUZZLES : PuzzleList_Frame()
        Case SCREEN_PUZZLE  : PuzzlePlay_Frame()
        Case SCREEN_FAMOUS  : FamousList_Frame()
        Case SCREEN_VIEWER  : Viewer_Frame()
        Case SCREEN_PROFILE : Profile_Frame()
        Case SCREEN_TOURNAMENT : Tournament_Frame()
        Case SCREEN_REVIEW  : Review_Frame()
        Case SCREEN_ANALYZE : Analyze_Frame()
        Case SCREEN_ONLINE  : Online_Frame()
        Case SCREEN_ONLINE_GAME : OnlineGame_Frame()
        Case SCREEN_ONLINE_PROFILE : OnlineProfile_Frame()
        Case SCREEN_ONLINE_LEADERBOARD : OnlineLeaderboard_Frame()
        End Select
        UI_EndFrame()
    Next
    Gfx_SaveScreenshot(outDir & "/" & fileName)
    ConsoleLine("  " & fileName)
End Sub

Sub RunScreenshots(ByRef outDir As Const String)
    UI.fakeInput = True
    AppConfig.animationMs = 0
    '' Never touch the player's real saved games or settings.
    Settings_SetDataDir(outDir)
    Save_SetDirectory(outDir & "/saves")
    Save_EnsureDirectory()
    Famous_Init(outDir & "/beginnerchess.db", ExePath() & "/data/games/famous.pgn", ExePath() & "/data/openings/book.txt")
    Profile_Init(outDir, "")
    Progress_SetLessonDone("board") : Progress_SetLessonDone("notation") : Progress_SetPuzzleSolved("m1-01")
    Scope
        '' A few sample games so the profile screen has something to show.
        Dim As GameRecord r
        r.kind = GK_FREE : r.opponent = "Computer (Beginner)" : r.oppRating = 500 : r.score = 1 : r.rated = True
        r.byMate = True : r.castled = True : r.level = 0
        Profile_RecordGame(r)
        r.kind = GK_CAREER : r.opponent = "Alex" : r.oppRating = 600 : r.score = 1 : r.byMate = False
        Profile_RecordGame(r)
        Profile_Current()->careerStage = 1
        r.opponent = "Maya" : r.oppRating = 800 : r.score = 0.5
        Profile_RecordGame(r)
        Ach_CheckAll(68, 44, False, False, 7)
        Tour_Start(0)
        Tour_RecordPlayerResult(2)
    End Scope
    ConsoleLine("Writing screenshots to " & outDir)
    Shot(outDir, "menu.bmp", SCREEN_MENU, 700, 220)
    Shot(outDir, "newgame.bmp", SCREEN_NEWGAME)
    NewGameOpts.opponent = OPP_COMPUTER
    NewGameOpts.difficulty = LEVEL_NORMAL
    NewGameOpts.style = STYLE_AGGRESSIVE
    Shot(outDir, "newgame_computer.bmp", SCREEN_NEWGAME, 512, 255)
    NewGameOpts.opponent = OPP_HUMAN
    Shot(outDir, "options.bmp", SCREEN_OPTIONS, 700, 160)
    Shot(outDir, "about.bmp", SCREEN_ABOUT)

    Dim As NewGameOptions opts
    Play_Start(opts)
    Play_DebugSelect("e2")
    Shot(outDir, "play_start.bmp", SCREEN_PLAY)

    Play_Start(opts)
    Play_DebugMoves("e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5 d5 exd5 Nxd5")
    Play_DebugSelect("g5")
    Shot(outDir, "play_classic.bmp", SCREEN_PLAY)
    Dim As Integer t
    Dim As String names(0 To 4) = {"classic", "wood", "marble", "simple", "contrast"}
    For t = 1 To THEME_COUNT - 1
        AppConfig.boardTheme = t
        Shot(outDir, "play_" & names(t) & ".bmp", SCREEN_PLAY)
    Next
    AppConfig.boardTheme = THEME_CLASSIC
    AppConfig.pieceSet = PIECESET_BOLD
    Shot(outDir, "play_bold.bmp", SCREEN_PLAY)
    AppConfig.pieceSet = PIECESET_CLASSIC

    Play_Start(opts)
    Play_DebugMoves("e4 e5 Nf3 d6 d4 Bg4 Bb5+")
    Play_DebugClick("e5")
    Play_DebugClick("e4")
    Shot(outDir, "play_illegal.bmp", SCREEN_PLAY)

    Play_Start(opts)
    Play_DebugFEN("8/1P3k2/8/8/8/8/5K2/8 w - - 0 1")
    Play_DebugPromotion("b7", "b8")
    Shot(outDir, "play_promotion.bmp", SCREEN_PLAY)

    Play_Start(opts)
    Play_DebugMoves("Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1")
    Play_DebugClick("f6")
    Play_DebugClick("g8")
    Shot(outDir, "play_claim.bmp", SCREEN_PLAY)

    '' Against the computer: thinking, then its reply.
    Dim As NewGameOptions vsc
    vsc.opponent = OPP_COMPUTER : vsc.difficulty = LEVEL_NORMAL : vsc.style = STYLE_BALANCED
    Play_Start(vsc)
    Play_DebugMoves("e4")
    Shot(outDir, "vs_thinking.bmp", SCREEN_PLAY)
    Dim As Double t0 = Timer
    Do While Play_DebugMoveCount() < 2 AndAlso Timer - t0 < 10
        UI_BeginFrame() : Play_Frame() : UI_EndFrame()
        Sleep 20, 1
    Loop
    Shot(outDir, "vs_reply.bmp", SCREEN_PLAY)

    '' Opening name, Save/Share menu, save and load screens, import.
    Play_Start(opts)
    Play_DebugMoves("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6")
    Shot(outDir, "play_opening.bmp", SCREEN_PLAY)
    Play_DebugOpenFileMenu()
    Shot(outDir, "play_filemenu.bmp", SCREEN_PLAY)
    Dim As String errMsg
    Play_SaveToSlot(2, errMsg)
    Play_Autosave()
    SaveLoad_Begin(SLMODE_SAVE, SCREEN_PLAY)
    Shot(outDir, "save.bmp", SCREEN_SAVELOAD)
    SaveLoad_Begin(SLMODE_LOAD, SCREEN_NEWGAME)
    Shot(outDir, "load.bmp", SCREEN_SAVELOAD)
    Shot(outDir, "menu_continue.bmp", SCREEN_MENU)
    Menu_DebugOpenFenDialog("8/8/4k3/8/2Q5/8/4K3/8 w - - 0 1")
    Shot(outDir, "newgame_fen.bmp", SCREEN_NEWGAME)
    Import_Begin(SCREEN_NEWGAME)
    Shot(outDir, "import.bmp", SCREEN_IMPORT)

    '' Learn Chess and puzzles
    Shot(outDir, "lessons.bmp", SCREEN_LESSONS)
    Learn_DebugLesson("knight", 0)
    Shot(outDir, "lesson_page.bmp", SCREEN_LESSON)
    Learn_DebugLesson("fork", 1)
    Shot(outDir, "lesson_task.bmp", SCREEN_LESSON)
    Learn_DebugLesson("romantic", 1)
    Shot(outDir, "lesson_history.bmp", SCREEN_LESSON)
    Shot(outDir, "puzzles.bmp", SCREEN_PUZZLES)
    Learn_DebugPuzzle("m2-02", 2)
    Shot(outDir, "puzzle.bmp", SCREEN_PUZZLE)

    '' Profile and tournaments
    Shot(outDir, "profile.bmp", SCREEN_PROFILE, 700, 160)
    Shot(outDir, "tournament.bmp", SCREEN_TOURNAMENT)
    Play_StartRated(GK_TOURNAMENT, *Tour_Opponent(0, 1), SIDE_BLACK, -1)
    Shot(outDir, "play_tournament.bmp", SCREEN_PLAY)
    UI_ShowToast("Achievement unlocked!", "First Victory")
    Shot(outDir, "toast.bmp", SCREEN_MENU)

    '' Practice, review, analysis
    UI_ClearToasts()
    Play_StartPractice(opts)
    Play_DebugMoves("e4 e5 Nf3 Nc6 Bc4 Nd4")
    Play_DebugPractice()
    Shot(outDir, "practice.bmp", SCREEN_PLAY)
    Scope
        Static rg As ChessGame
        Dim As String rerr
        Game_New(rg)
        Game_PlayMoveText(rg, "e4", rerr) : Game_PlayMoveText(rg, "e5", rerr)
        Game_PlayMoveText(rg, "Nf3", rerr) : Game_PlayMoveText(rg, "Nc6", rerr)
        Game_PlayMoveText(rg, "Bc4", rerr) : Game_PlayMoveText(rg, "Nd4", rerr)
        Game_PlayMoveText(rg, "Nxe5", rerr) : Game_PlayMoveText(rg, "Qg5", rerr)
        Game_PlayMoveText(rg, "Nxf7", rerr) : Game_PlayMoveText(rg, "Qxg2", rerr)
        Review_Start(rg, SCREEN_MENU, False)
        Review_DebugFinish(6)
        Shot(outDir, "review.bmp", SCREEN_REVIEW)
    End Scope
    Analyze_Start("r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3", SCREEN_MENU)
    Dim As Double at0 = Timer
    Do While Timer - at0 < 3.5
        UI_BeginFrame() : Analyze_Frame() : UI_EndFrame()
        Sleep 50, 1
    Loop
    Shot(outDir, "analyze.bmp", SCREEN_ANALYZE)

    '' Play Online (sample server data; no network needed)
    Online_DebugSample(False)
    Shot(outDir, "online.bmp", SCREEN_ONLINE)
    Online_DebugSample(True)
    Shot(outDir, "online_game.bmp", SCREEN_ONLINE_GAME)
    Online_ClearGame()
    Online_DebugProfileSample()
    Shot(outDir, "online_profile.bmp", SCREEN_ONLINE_PROFILE)

    '' Famous games
    Shot(outDir, "famous.bmp", SCREEN_FAMOUS, 600, 300)
    Viewer_DebugShow(1, 35)
    Shot(outDir, "viewer.bmp", SCREEN_VIEWER)

    Play_Start(opts)
    Play_DebugMoves("f3 e5 g4 Qh4#")
    Shot(outDir, "play_checkmate.bmp", SCREEN_PLAY)

    '' A rated career game is added to the player's tournament PGN file.
    Play_StartRated(GK_CAREER, *Career_Opponent(0), SIDE_WHITE, 0)
    Play_DebugMoves("f3 e5 g4 Qh4#")
    Shot(outDir, "career_loss.bmp", SCREEN_PLAY)

    ConsoleLine("  rendered every lesson step and puzzle: " & Learn_RenderAll() & " frames")
End Sub
