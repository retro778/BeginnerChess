'' =====================================================================
'' BeginnerChess - tests/test_audio.bas
'' Tests for the sound synthesiser and BASS loading.
''   test_audio              synthesis checks + BASS start-up (+ plays a sound)
''   test_audio --write DIR  writes every built-in sound as DIR/<name>.wav
'' =====================================================================
#include once "../modules/audio.bi"
#include once "testutil.bi"
#include once "../modules/settings.bi"
#include once "file.bi"

Dim Shared TestsPassed As Integer = 0
Dim Shared TestsFailed As Integer = 0

Sub Check(ByVal ok As Boolean, ByRef testName As Const String, ByRef detail As Const String = "")
    If ok Then
        TestsPassed += 1
    Else
        TestsFailed += 1
        Print "  FAIL: " & testName;
        If detail <> "" Then Print "  (" & detail & ")" Else Print
    End If
End Sub

'' Checks a WAV buffer: header, size and peak level.
Function CheckWav(ByVal buf As UByte Ptr, ByVal size As Integer, ByRef nm As Const String, ByRef peakOut As Single) As Boolean
    If size <= 44 OrElse buf = 0 Then Return False
    Dim As String hdr = Chr(buf[0], buf[1], buf[2], buf[3]) & Chr(buf[8], buf[9], buf[10], buf[11])
    If hdr <> "RIFFWAVE" Then Return False
    Dim As Short Ptr pcm = Cast(Short Ptr, buf + 44)
    Dim As Integer n = (size - 44) \ 2, i, peak = 0
    For i = 0 To n - 1
        If Abs(CInt(pcm[i])) > peak Then peak = Abs(CInt(pcm[i]))
    Next
    peakOut = peak / 32767
    '' Not silent, not clipped, no click at the start.
    Return peak > 3000 AndAlso peak < 32767 AndAlso Abs(CInt(pcm[0])) < 2000
End Function

Sub WriteFile(ByRef fn As Const String, ByVal buf As UByte Ptr, ByVal size As Integer)
    Dim As Integer f = FreeFile
    If Open(fn For Binary Access Write As #f) = 0 Then
        Put #f, , *buf, size
        Close #f
    End If
End Sub

If Command(1) = "--write" Then
    Dim As String d = Command(2)
    If d = "" Then d = "."
    Dim As Integer id
    For id = 0 To SND_COUNT - 1
        Dim As UByte Ptr buf
        Dim As Integer size = Audio_SynthesizeWav(id, buf)
        WriteFile(d & "/" & Audio_SoundName(id) & ".wav", buf, size)
        Deallocate buf
    Next
    Dim As UByte Ptr mb
    Dim As Integer ms = Audio_SynthesizeMusic(mb)
    WriteFile(d & "/music.wav", mb, ms)
    Deallocate mb
    Print "Sounds written to " & d
    End 0
End If

Sub TestSettings()
    Print "Settings file..."
    Dim As String fn = Test_TempDir("cm_test_settings.ini")
    Kill fn
    Dim As AppSettings a, b
    Check Settings_Load(b, fn) = False, "missing file reports False"
    Dim As Boolean defaultsOk = (b.screenW = 1024) AndAlso b.soundOn
    Check defaultsOk, "missing file gives defaults"
    Settings_Defaults(a)
    a.boardTheme = 3 : a.pieceSet = 1 : a.fullscreen = True : a.musicOn = True
    a.soundVolume = 35 : a.musicVolume = 64 : a.animationMs = 320 : a.newDifficulty = 4
    a.screenW = 1280 : a.screenH = 960 : a.showCoordinates = False
    Check Settings_Save(a, fn), "settings saved"
    Check Settings_Load(b, fn), "settings loaded"
    Dim As Boolean same = (b.boardTheme = 3) AndAlso (b.pieceSet = 1) AndAlso (b.soundVolume = 35) _
        AndAlso (b.musicVolume = 64) AndAlso (b.animationMs = 320) AndAlso (b.newDifficulty = 4) _
        AndAlso (b.screenW = 1280) AndAlso (b.screenH = 960)
    If Not b.fullscreen OrElse Not b.musicOn OrElse b.showCoordinates Then same = False
    Check same, "all values survive a save/load round trip"
    '' A damaged file: nonsense lines and out-of-range values.
    Dim As Integer f = FreeFile
    Open fn For Output As #f
    Print #f, "this is not a setting"
    Print #f, "boardTheme=99"
    Print #f, "soundVolume=-20"
    Print #f, "screenWidth=abc"
    Print #f, "musicVolume=150"
    Print #f, Chr(0, 255) & "=="
    Close #f
    Check Settings_Load(b, fn), "damaged file still loads"
    Check b.boardTheme = 4 AndAlso b.soundVolume = 0 AndAlso b.musicVolume = 100 AndAlso b.screenW = 1024, _
          "bad values are clamped or ignored", b.boardTheme & " " & b.soundVolume & " " & b.musicVolume & " " & b.screenW
    Kill fn
    Check Len(Settings_DataDir()) > 0, "data folder found", Settings_DataDir()

    '' Files of the former program name ChessMaster are still used.
    Dim As String md = Test_TempDir("cm_test_migrate")
    Test_RemoveTree(md)
    Settings_SetDataDir(md)
    Check Right(Settings_FileName(), 18) = "/beginnerchess.ini", "settings file has the new name", Settings_FileName()
    Check Settings_ReadFileName() = Settings_FileName(), "no old file: read the new one"
    a.boardTheme = 2
    Settings_Save(a, md & "/chessmaster.ini")
    Check Right(Settings_ReadFileName(), 16) = "/chessmaster.ini", "old chessmaster.ini is read when the new file is missing"
    Check Settings_Load(b, Settings_ReadFileName()) AndAlso b.boardTheme = 2, "old settings loaded"
    Settings_Save(b, Settings_FileName())
    Check Settings_ReadFileName() = Settings_FileName(), "once saved, the new file is used"
    f = FreeFile
    Open md & "/chessmaster.db" For Output As #f : Print #f, "db" : Close #f
    Settings_MigrateFile(md & "/chessmaster.db", md & "/beginnerchess.db")
    Check FileExists(md & "/beginnerchess.db") AndAlso (FileExists(md & "/chessmaster.db") = 0), "old database file renamed"
    Test_RemoveTree(md)
End Sub

Print "BeginnerChess audio and settings tests"
TestSettings()
Dim As Integer id
Dim As Double t0 = Timer
For id = 0 To SND_COUNT - 1
    Dim As UByte Ptr buf
    Dim As Single peak
    Dim As Integer size = Audio_SynthesizeWav(id, buf)
    Dim As Double secs = (size - 44) / 2 / 44100
    Check CheckWav(buf, size, Audio_SoundName(id), peak), "sound '" & Audio_SoundName(id) & "' is a valid WAV", _
          "peak " & CInt(peak * 100) & "%, " & CInt(secs * 1000) & " ms"
    Check secs > 0.02 AndAlso secs < 2.5, "sound '" & Audio_SoundName(id) & "' has a sensible length", Str(secs)
    Deallocate buf
Next
Dim As UByte Ptr mb
Dim As Single mpeak
Dim As Integer ms = Audio_SynthesizeMusic(mb)
Check CheckWav(mb, ms, "music", mpeak), "music is a valid WAV"
Dim As Double musicSecs = (ms - 44) / 2 / 22050
Check musicSecs > 20 AndAlso musicSecs < 60, "music loop length", Str(musicSecs)
'' Seamless loop: the end and the start must join smoothly.
Dim As Short Ptr pcm = Cast(Short Ptr, mb + 44)
Dim As Integer nS = (ms - 44) \ 2
Check Abs(CInt(pcm[nS - 1]) - CInt(pcm[0])) < 3000, "music loops without a click", pcm[nS - 1] & " -> " & pcm[0]
Deallocate mb
Print "  synthesis took " & CInt((Timer - t0) * 1000) & " ms"

'' BASS: available here or not, the program must cope.
Dim As Boolean ok = Audio_Init(ExePath() & "/..")
Print "  " & Audio_StatusText()
Check ok = Audio_Available(), "status consistent"
If ok Then
    Audio_SetSound(True, 60)
    Audio_Play(SND_MOVE)
    Sleep 250, 1
    Audio_Play(SND_CHECKMATE)
    Sleep 900, 1
End If
Audio_Play(SND_CAPTURE)       '' safe even when audio is off
Audio_Shutdown()
Audio_Shutdown()              '' twice is harmless
Check Audio_Available() = False, "shut down"
Print
Print "Passed: " & TestsPassed & "   Failed: " & TestsFailed
If TestsFailed > 0 Then End 1
End 0
