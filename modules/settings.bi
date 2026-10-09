'' =====================================================================
'' BeginnerChess - settings.bi
'' User preferences, stored in a simple "key=value" text file
'' (beginnerchess.ini) in the data folder:
''   * the program's own folder when it is writable (portable use), else
''   * Linux: ~/.beginnerchess   Windows: %APPDATA%\BeginnerChess
''     (the folders of the former name ChessMaster are renamed once)
'' Unknown keys are ignored and bad values are replaced by defaults, so
'' a damaged settings file can never stop the program from starting.
'' =====================================================================
#pragma once

Type AppSettings
    screenW         As Integer
    screenH         As Integer
    fullscreen      As Boolean
    boardTheme      As Integer      '' THEME_* (board.bi)
    pieceSet        As Integer      '' PIECESET_* (pieces.bi)
    showLegalMoves  As Boolean
    showCoordinates As Boolean
    animationMs     As Integer      '' 0 = no animation
    beginnerHints   As Boolean
    soundOn         As Boolean
    musicOn         As Boolean
    soundVolume     As Integer      '' 0..100
    musicVolume     As Integer      '' 0..100
    '' Last choices on the New Game screen
    newOpponent     As Integer
    newPlayAs       As Integer
    newDifficulty   As Integer
    newStyle        As Integer
    activeProfile   As String       '' id of the player profile in use
    achievementsOn  As Boolean      '' show achievements and their pop-ups
    '' Play Online
    onlineServer    As String       '' wss:// address of the multiplayer server
    onlineNickname  As String       '' last guest nickname
    onlineUser      As String       '' last account name used to log in (never the password)
    onlineMinutes   As Integer      '' index into 3|5|10|15|30
    onlineIncrement As Integer      '' index into 0|2|5|10
End Type

Const ONLINE_SERVER_DEFAULT = "wss://freedomnet.tech/chess/ws"

Extern AppConfig As AppSettings

Declare Sub Settings_Defaults(ByRef s As AppSettings)
'' Clamps every value into its valid range.
Declare Sub Settings_Validate(ByRef s As AppSettings)
Declare Function Settings_Load(ByRef s As AppSettings, ByRef fileName As Const String) As Boolean
Declare Function Settings_Save(ByRef s As AppSettings, ByRef fileName As Const String) As Boolean

'' Folder for settings, saved games and other user files (created if needed).
Declare Function Settings_DataDir() As String
Declare Sub Settings_SetDataDir(ByRef path As Const String)
Declare Function Settings_FileName() As String
Declare Function Settings_ReadFileName() As String
Declare Sub Settings_MigrateFile(ByRef oldFile As Const String, ByRef newFile As Const String)
