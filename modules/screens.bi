'' =====================================================================
'' BeginnerChess - screens.bi
'' The program's screens. Each *_Frame function draws one frame, handles
'' input, and returns the screen to show next.
'' =====================================================================
#pragma once
#include once "game.bi"
#include once "board.bi"
#include once "gui.bi"
#include once "settings.bi"
#include once "explain.bi"
#include once "engine.bi"
#include once "savegame.bi"
#include once "clipboard.bi"
#include once "audio.bi"
#include once "profile.bi"
#include once "career.bi"
#include once "coach.bi"

Enum AppScreen
    SCREEN_MENU = 0
    SCREEN_NEWGAME
    SCREEN_PLAY
    SCREEN_OPTIONS
    SCREEN_ABOUT
    SCREEN_SAVELOAD
    SCREEN_IMPORT
    SCREEN_LESSONS
    SCREEN_LESSON
    SCREEN_PUZZLES
    SCREEN_PUZZLE
    SCREEN_FAMOUS
    SCREEN_VIEWER
    SCREEN_PROFILE
    SCREEN_TOURNAMENT
    SCREEN_REVIEW
    SCREEN_ANALYZE
    SCREEN_ONLINE
    SCREEN_ONLINE_GAME
    SCREEN_ONLINE_PROFILE
    SCREEN_ONLINE_LEADERBOARD
    SCREEN_QUIT
End Enum

Enum OpponentKind
    OPP_HUMAN = 0
    OPP_COMPUTER
End Enum

Type NewGameOptions
    opponent   As Integer    '' OPP_*
    playAs     As Integer    '' 0 White, 1 Black, 2 Random
    difficulty As Integer    '' 0..4 (Beginner .. Advanced)
    style      As Integer    '' EngineStyle
End Type

Extern NewGameOpts As NewGameOptions

'' Shared decoration
Declare Sub Screen_DrawHeader(ByRef title As Const String)

'' menu.bas
Declare Function Menu_Frame() As Integer
Declare Function NewGame_Frame() As Integer
Declare Function Options_Frame() As Integer
Declare Function About_Frame() As Integer

'' play.bas
Declare Sub Play_Start(ByRef opts As NewGameOptions)
Declare Function Play_Frame() As Integer
Declare Sub Play_Shutdown()
'' Saving, loading and other ways to start a game.
Declare Function Play_SaveToSlot(ByVal slot As Integer, ByRef errMsg As String) As Boolean
Declare Function Play_LoadFromSlot(ByVal slot As Integer, ByRef errMsg As String) As Boolean
Declare Function Play_StartFromFEN(ByRef opts As NewGameOptions, ByRef fen As Const String, ByRef errMsg As String) As Boolean
Declare Function Play_StartFromPGN(ByRef opts As NewGameOptions, ByRef gameText As Const String, ByRef errMsg As String) As Boolean
'' Saves the running game to the autosave slot (or removes the autosave
'' when the game is finished).
Declare Sub Play_Autosave()
'' Continues game g from after 'plies' half-moves against the computer.
Declare Function Play_StartFromGamePrefix(ByRef opts As NewGameOptions, ByRef g As ChessGame, _
                                          ByVal plies As Integer, ByRef errMsg As String) As Boolean
Declare Sub Play_ShowMessage(ByRef text As Const String)

'' files.bas: save/load and PGN import screens
Enum SaveLoadMode
    SLMODE_SAVE = 0
    SLMODE_LOAD
End Enum
Declare Sub SaveLoad_Begin(ByVal mode As Integer, ByVal returnScreen As Integer)
Declare Function SaveLoad_Frame() As Integer
'' mode 0 = open a game to play, 1 = add all games of a file to the library
Declare Sub Import_Begin(ByVal returnScreen As Integer, ByVal mode As Integer = 0)
Declare Function Import_Frame() As Integer

'' learn.bas: lessons and puzzles
Declare Function LessonList_Frame() As Integer
Declare Function LessonPlay_Frame() As Integer
Declare Function PuzzleList_Frame() As Integer
Declare Function PuzzlePlay_Frame() As Integer
Declare Sub Learn_DebugLesson(ByRef id As Const String, ByVal stepIdx As Integer)
Declare Sub Learn_DebugPuzzle(ByRef id As Const String, ByVal hintLevel As Integer)
Declare Function Learn_RenderAll() As Integer

'' famousui.bas: Famous Games
Declare Function FamousList_Frame() As Integer
Declare Function Viewer_Frame() As Integer
Declare Sub Viewer_DebugShow(ByVal index As Integer, ByVal ply As Integer)

'' Rated games against career / tournament opponents (no take-backs).
Declare Sub Play_StartRated(ByVal kind As Integer, ByRef opp As Opponent, ByVal humanSide As Integer, _
                            ByVal careerIndex As Integer)

'' Practice game: take-backs, hints, threats, mistake warnings, side switching.
Declare Sub Play_StartPractice(ByRef opts As NewGameOptions)
'' New Game screen in practice mode (title, START begins a practice game).
Declare Sub NewGame_SetPractice(ByVal practice As Boolean)

'' review.bas / analyzeui.bas
Declare Sub Review_Start(ByRef g As ChessGame, ByVal returnScreen As Integer, ByVal flipped As Boolean)
Declare Function Review_Frame() As Integer
Declare Sub Review_DebugFinish(ByVal ply As Integer)
Declare Sub Analyze_Start(ByRef fen As Const String, ByVal returnScreen As Integer)
Declare Function Analyze_Frame() As Integer

'' profileui.bas / tournamentui.bas
Declare Function Profile_Frame() As Integer
Declare Function Tournament_Frame() As Integer
'' Unlocks earned achievements and shows a pop-up for each new one.
Declare Sub App_CheckAchievements()
'' Rating a computer level stands for (Beginner 500 ... Advanced 1700).
Declare Function LevelRating(ByVal level As Integer) As Integer

'' Hooks used to produce automated screenshots / tests.
Declare Function Play_DebugMoves(ByRef moves As Const String) As Boolean
Declare Sub Play_DebugSelect(ByRef sqName As Const String)
Declare Sub Play_DebugPromotion(ByRef fromName As Const String, ByRef toName As Const String)
Declare Sub Play_DebugClick(ByRef sqName As Const String)
Declare Function Play_DebugFEN(ByRef fen As Const String) As Boolean
Declare Function Play_DebugMoveCount() As Integer
Declare Sub Play_DebugPractice()

'' Play Online (onlineui.bas)
Declare Sub Online_Enter()
Declare Function Online_Frame() As Integer
Declare Function OnlineGame_Frame() As Integer
'' Every frame, every screen: keeps the connection alive, handles server events.
Declare Function OnlineUI_Pump(ByVal currentScreen As Integer) As Integer
Declare Sub Online_DebugSample(ByVal withGame As Boolean)
Declare Sub Online_ShowProfile(ByRef username As Const String)
Declare Function OnlineProfile_Frame() As Integer
Declare Sub Online_DebugProfileSample()
Declare Function OnlineLeaderboard_Frame() As Integer
Declare Function Play_TournamentPgnFile() As String
Declare Function Viewer_StartPgn(ByRef gameText As Const String, ByVal returnScreen As Integer, _
                                 ByRef errMsg As String) As Boolean
Declare Sub Play_DebugOpenFileMenu()
Declare Sub Menu_DebugOpenFenDialog(ByRef text As Const String)
