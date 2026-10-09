'' =====================================================================
'' BeginnerChess - settings.bas
'' See settings.bi.
'' =====================================================================
#include once "settings.bi"
#include once "file.bi"
#include once "dir.bi"

Dim Shared AppConfig As AppSettings
Dim Shared DataDir As String

Sub Settings_Defaults(ByRef s As AppSettings)
    s.screenW = 1024
    s.screenH = 768
    s.fullscreen = False
    s.boardTheme = 0
    s.pieceSet = 0
    s.showLegalMoves = True
    s.showCoordinates = True
    s.animationMs = 180
    s.beginnerHints = True
    s.soundOn = True
    s.musicOn = False
    s.soundVolume = 80
    s.musicVolume = 50
    s.newOpponent = 1
    s.newPlayAs = 0
    s.newDifficulty = 0
    s.newStyle = 0
    s.activeProfile = ""
    s.achievementsOn = True
    s.onlineServer = ONLINE_SERVER_DEFAULT
    s.onlineNickname = ""
    s.onlineUser = ""
    s.onlineMinutes = 2
    s.onlineIncrement = 0
End Sub

Private Function Clamp(ByVal v As Integer, ByVal lo As Integer, ByVal hi As Integer) As Integer
    If v < lo Then Return lo
    If v > hi Then Return hi
    Return v
End Function

Sub Settings_Validate(ByRef s As AppSettings)
    s.screenW = Clamp(s.screenW, 1024, 3840)
    s.screenH = Clamp(s.screenH, 768, 2160)
    s.boardTheme = Clamp(s.boardTheme, 0, 4)
    s.pieceSet = Clamp(s.pieceSet, 0, 1)
    s.animationMs = Clamp(s.animationMs, 0, 1000)
    s.soundVolume = Clamp(s.soundVolume, 0, 100)
    s.musicVolume = Clamp(s.musicVolume, 0, 100)
    s.newOpponent = Clamp(s.newOpponent, 0, 1)
    s.newPlayAs = Clamp(s.newPlayAs, 0, 2)
    s.newDifficulty = Clamp(s.newDifficulty, 0, 4)
    s.newStyle = Clamp(s.newStyle, 0, 5)
    s.onlineMinutes = Clamp(s.onlineMinutes, 0, 4)
    s.onlineIncrement = Clamp(s.onlineIncrement, 0, 3)
    If Trim(s.onlineServer) = "" Then s.onlineServer = ONLINE_SERVER_DEFAULT
End Sub

Private Function ParseBool(ByRef v As Const String, ByVal def As Boolean) As Boolean
    Select Case LCase(Trim(v))
    Case "1", "true", "yes", "on" : Return True
    Case "0", "false", "no", "off" : Return False
    End Select
    Return def
End Function

Private Function ParseInt(ByRef v As Const String, ByVal def As Integer) As Integer
    Dim As String t = Trim(v)
    If t = "" Then Return def
    Dim As Integer i
    For i = 1 To Len(t)
        Dim As String c = Mid(t, i, 1)
        If (c < "0" OrElse c > "9") AndAlso Not (i = 1 AndAlso c = "-") Then Return def
    Next
    Return ValInt(t)
End Function

Function Settings_Load(ByRef s As AppSettings, ByRef fileName As Const String) As Boolean
    Settings_Defaults(s)
    Dim As Integer f = FreeFile
    If Open(fileName For Input As #f) <> 0 Then Return False
    Dim As String ln
    Do While Not EOF(f)
        Line Input #f, ln
        ln = Trim(ln, Any " " & Chr(9, 13))
        If ln = "" OrElse Left(ln, 1) = "#" OrElse Left(ln, 1) = ";" OrElse Left(ln, 1) = "[" Then Continue Do
        Dim As Integer eq = InStr(ln, "=")
        If eq = 0 Then Continue Do
        Dim As String k = LCase(Trim(Left(ln, eq - 1))), v = Trim(Mid(ln, eq + 1))
        Select Case k
        Case "screenwidth"     : s.screenW = ParseInt(v, s.screenW)
        Case "screenheight"    : s.screenH = ParseInt(v, s.screenH)
        Case "fullscreen"      : s.fullscreen = ParseBool(v, s.fullscreen)
        Case "boardtheme"      : s.boardTheme = ParseInt(v, s.boardTheme)
        Case "pieceset"        : s.pieceSet = ParseInt(v, s.pieceSet)
        Case "showlegalmoves"  : s.showLegalMoves = ParseBool(v, s.showLegalMoves)
        Case "showcoordinates" : s.showCoordinates = ParseBool(v, s.showCoordinates)
        Case "animationms"     : s.animationMs = ParseInt(v, s.animationMs)
        Case "beginnerhints"   : s.beginnerHints = ParseBool(v, s.beginnerHints)
        Case "sound"           : s.soundOn = ParseBool(v, s.soundOn)
        Case "music"           : s.musicOn = ParseBool(v, s.musicOn)
        Case "soundvolume"     : s.soundVolume = ParseInt(v, s.soundVolume)
        Case "musicvolume"     : s.musicVolume = ParseInt(v, s.musicVolume)
        Case "newopponent"     : s.newOpponent = ParseInt(v, s.newOpponent)
        Case "newplayas"       : s.newPlayAs = ParseInt(v, s.newPlayAs)
        Case "newdifficulty"   : s.newDifficulty = ParseInt(v, s.newDifficulty)
        Case "newstyle"        : s.newStyle = ParseInt(v, s.newStyle)
        Case "activeprofile"   : s.activeProfile = Left(v, 32)
        Case "achievements"    : s.achievementsOn = ParseBool(v, s.achievementsOn)
        Case "onlineserver"    : s.onlineServer = Left(Trim(v), 256)
        Case "onlinenickname"  : s.onlineNickname = Left(Trim(v), 16)
        Case "onlineuser"      : s.onlineUser = Left(Trim(v), 16)
        Case "onlineminutes"   : s.onlineMinutes = ParseInt(v, s.onlineMinutes)
        Case "onlineincrement" : s.onlineIncrement = ParseInt(v, s.onlineIncrement)
        End Select
    Loop
    Close #f
    Settings_Validate(s)
    Return True
End Function

Function Settings_Save(ByRef s As AppSettings, ByRef fileName As Const String) As Boolean
    Dim As String tmp = fileName & ".tmp"
    Dim As Integer f = FreeFile
    If Open(tmp For Output As #f) <> 0 Then Return False
    #define B(x) IIf(x, "1", "0")
    Print #f, "# Beginner Chess settings (edit with care; bad values are reset)"
    Print #f, "screenWidth=" & s.screenW
    Print #f, "screenHeight=" & s.screenH
    Print #f, "fullscreen=" & B(s.fullscreen)
    Print #f, "boardTheme=" & s.boardTheme
    Print #f, "pieceSet=" & s.pieceSet
    Print #f, "showLegalMoves=" & B(s.showLegalMoves)
    Print #f, "showCoordinates=" & B(s.showCoordinates)
    Print #f, "animationMs=" & s.animationMs
    Print #f, "beginnerHints=" & B(s.beginnerHints)
    Print #f, "sound=" & B(s.soundOn)
    Print #f, "music=" & B(s.musicOn)
    Print #f, "soundVolume=" & s.soundVolume
    Print #f, "musicVolume=" & s.musicVolume
    Print #f, "newOpponent=" & s.newOpponent
    Print #f, "newPlayAs=" & s.newPlayAs
    Print #f, "newDifficulty=" & s.newDifficulty
    Print #f, "newStyle=" & s.newStyle
    Print #f, "activeProfile=" & s.activeProfile
    Print #f, "achievements=" & B(s.achievementsOn)
    Print #f, "onlineServer=" & s.onlineServer
    Print #f, "onlineNickname=" & s.onlineNickname
    Print #f, "onlineUser=" & s.onlineUser
    Print #f, "onlineMinutes=" & s.onlineMinutes
    Print #f, "onlineIncrement=" & s.onlineIncrement
    #undef B
    Close #f
    If FileExists(fileName) Then Kill fileName
    Return Name(tmp, fileName) = 0
End Function

'' ---------------------------------------------------------------------
'' Data folder
'' ---------------------------------------------------------------------
Private Function IsWritable(ByRef folder As Const String) As Boolean
    Dim As String probe = folder & "/.beginnerchess_write_test"
    Dim As Integer f = FreeFile
    If Open(probe For Output As #f) <> 0 Then Return False
    Close #f
    Kill probe
    Return True
End Function

Sub Settings_SetDataDir(ByRef path As Const String)
    DataDir = path
    If Dir(DataDir, fbDirectory) = "" Then MkDir DataDir
End Sub

Function Settings_DataDir() As String
    If DataDir <> "" Then Return DataDir
    If IsWritable(ExePath()) Then
        DataDir = ExePath()
    Else
#ifdef __FB_WIN32__
        Dim As String home = Environ("APPDATA")
        If home = "" Then home = Environ("USERPROFILE")
        DataDir = home & "\BeginnerChess"
        Dim As String oldDir = home & "\ChessMaster"       '' folder of the program's former name
#else
        Dim As String home = Environ("HOME")
        If home = "" Then home = "/tmp"
        DataDir = home & "/.beginnerchess"
        Dim As String oldDir = home & "/.chessmaster"       '' folder of the program's former name
#endif
        '' Players of the former "ChessMaster" keep their profiles and saves.
        If Dir(DataDir, fbDirectory) = "" AndAlso Dir(oldDir, fbDirectory) <> "" Then
            If Name(oldDir, DataDir) <> 0 Then DataDir = oldDir
        End If
        If Dir(DataDir, fbDirectory) = "" Then MkDir DataDir
    End If
    Return DataDir
End Function

Function Settings_FileName() As String
    Return Settings_DataDir() & "/beginnerchess.ini"
End Function

'' The file to read the settings from: beginnerchess.ini, or the settings
'' file of the program's former name (chessmaster.ini) when only that one
'' exists. Settings are always saved under the new name.
Function Settings_ReadFileName() As String
    Dim As String f = Settings_FileName()
    If Dir(f) = "" Then
        Dim As String legacy = Settings_DataDir() & "/chessmaster.ini"
        If Dir(legacy) <> "" Then Return legacy
    End If
    Return f
End Function

'' Renames a data file of the program's former name (e.g. chessmaster.db)
'' when the new file does not exist yet.
Sub Settings_MigrateFile(ByRef oldFile As Const String, ByRef newFile As Const String)
    If Dir(newFile) = "" AndAlso Dir(oldFile) <> "" Then Name(oldFile, newFile)
End Sub
