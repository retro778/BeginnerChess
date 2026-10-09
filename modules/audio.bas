'' =====================================================================
'' BeginnerChess - audio.bas
'' See audio.bi.
'' =====================================================================
#include once "audio.bi"
#include once "file.bi"
#include once "dir.bi"

'' ---------------------------------------------------------------------
'' BASS, loaded dynamically. Types and constants follow bass.bi (2.4).
'' ---------------------------------------------------------------------
#ifdef __FB_WIN32__
    #define BASSCALL Stdcall
    #define BASS_FILE_NAME "bass.dll"
#else
    #define BASSCALL Cdecl
    #define BASS_FILE_NAME "libbass.so"
#endif

Const BASS_SAMPLE_LOOP = 4
Const BASS_SAMPLE_OVER_POS = &h20000
Const BASS_ATTRIB_VOL = 2
Const BASS_ACTIVE_STOPPED = 0
Const BASS_ERROR_ALREADY = 14

Type FnInit As Function BASSCALL (ByVal device As Long, ByVal freq As ULong, ByVal flags As ULong, _
                                  ByVal win As Any Ptr, ByVal dsguid As Any Ptr) As Long
Type FnFree As Function BASSCALL () As Long
Type FnGetVersion As Function BASSCALL () As ULong
Type FnErrorGetCode As Function BASSCALL () As Long
Type FnSampleLoad As Function BASSCALL (ByVal mem As Long, ByVal file As Any Ptr, ByVal offset As ULongInt, _
                                        ByVal length As ULong, ByVal max As ULong, ByVal flags As ULong) As ULong
Type FnSampleGetChannel As Function BASSCALL (ByVal handle As ULong, ByVal flags As ULong) As ULong
Type FnStreamCreateFile As Function BASSCALL (ByVal mem As Long, ByVal file As Any Ptr, ByVal offset As ULongInt, _
                                              ByVal length As ULongInt, ByVal flags As ULong) As ULong
Type FnStreamFree As Function BASSCALL (ByVal handle As ULong) As Long
Type FnChannelPlay As Function BASSCALL (ByVal handle As ULong, ByVal restart As Long) As Long
Type FnChannelStop As Function BASSCALL (ByVal handle As ULong) As Long
Type FnChannelSetAttribute As Function BASSCALL (ByVal handle As ULong, ByVal attrib As ULong, ByVal value As Single) As Long
Type FnChannelIsActive As Function BASSCALL (ByVal handle As ULong) As ULong

Dim Shared BassLib As Any Ptr = 0
Dim Shared pBASS_Init As FnInit
Dim Shared pBASS_Free As FnFree
Dim Shared pBASS_GetVersion As FnGetVersion
Dim Shared pBASS_ErrorGetCode As FnErrorGetCode
Dim Shared pBASS_SampleLoad As FnSampleLoad
Dim Shared pBASS_SampleGetChannel As FnSampleGetChannel
Dim Shared pBASS_StreamCreateFile As FnStreamCreateFile
Dim Shared pBASS_StreamFree As FnStreamFree
Dim Shared pBASS_ChannelPlay As FnChannelPlay
Dim Shared pBASS_ChannelStop As FnChannelStop
Dim Shared pBASS_ChannelSetAttribute As FnChannelSetAttribute
Dim Shared pBASS_ChannelIsActive As FnChannelIsActive

Dim Shared AudioReady As Boolean = False
Dim Shared AudioStatus As String
Dim Shared SoundOn As Boolean = True
Dim Shared SoundVol As Single = 0.8
Dim Shared MusicOn As Boolean = False
Dim Shared MusicVol As Single = 0.5
Dim Shared SampleHandle(0 To SND_COUNT - 1) As ULong
Dim Shared SampleData(0 To SND_COUNT - 1) As UByte Ptr   '' memory must outlive the samples
Dim Shared MusicData As UByte Ptr = 0
Dim Shared MusicSize As Integer = 0
Dim Shared MusicStream As ULong = 0
Dim Shared MusicFiles(0 To 63) As String
Dim Shared MusicFileCount As Integer = 0
Dim Shared MusicIndex As Integer = 0
Dim Shared AudioBase As String

Function Audio_SoundName(ByVal id As Integer) As String
    Select Case id
    Case SND_MOVE      : Return "move"
    Case SND_CAPTURE   : Return "capture"
    Case SND_CASTLE    : Return "castle"
    Case SND_PROMOTE   : Return "promote"
    Case SND_CHECK     : Return "check"
    Case SND_CHECKMATE : Return "checkmate"
    Case SND_ILLEGAL   : Return "illegal"
    Case SND_CLICK     : Return "click"
    Case SND_VICTORY   : Return "victory"
    Case SND_DEFEAT    : Return "defeat"
    Case SND_DRAW      : Return "draw"
    Case SND_SOLVED    : Return "solved"
    Case SND_START     : Return "start"
    End Select
    Return "unknown"
End Function

'' =====================================================================
'' Synthesiser
'' =====================================================================
Const SFX_RATE = 44100
Const MUSIC_RATE = 22050
Const PI2 = 6.283185307

'' A mono float buffer. When "wrap" is set, sound that runs past the end
'' continues at the start (used for a seamless music loop).
Type SynthBuffer
    rate As Integer
    n    As Integer
    wrap As Boolean
    s    As Single Ptr
End Type

Private Sub Buf_Create(ByRef b As SynthBuffer, ByVal rate As Integer, ByVal seconds As Double, ByVal wrap As Boolean = False)
    b.rate = rate
    b.n = Int(rate * seconds)
    b.wrap = wrap
    b.s = CAllocate(b.n * SizeOf(Single))
End Sub

Private Sub Buf_Free(ByRef b As SynthBuffer)
    If b.s Then Deallocate b.s
    b.s = 0
End Sub

Private Sub Buf_Add(ByRef b As SynthBuffer, ByVal i As Integer, ByVal v As Single)
    If i < 0 Then Exit Sub
    If i >= b.n Then
        If Not b.wrap Then Exit Sub
        i Mod= b.n
    End If
    b.s[i] += v
End Sub

'' Wave shapes: 0 sine, 1 triangle, 2 soft square
Private Function Wave(ByVal shape As Integer, ByVal ph As Double) As Single
    Dim As Double f = ph - Int(ph)
    Select Case shape
    Case 1 : Return 4 * Abs(f - 0.5) - 1
    Case 2
        Dim As Double v = Sin(PI2 * f) * 3
        If v > 1 Then v = 1
        If v < -1 Then v = -1
        Return v * 0.8
    End Select
    Return Sin(PI2 * f)
End Function

'' A tone with attack and exponential decay; freq may glide to freqEnd.
Private Sub AddTone(ByRef b As SynthBuffer, ByVal startSec As Double, ByVal freq As Double, ByVal durSec As Double, _
                    ByVal amp As Single, ByVal attackSec As Double, ByVal decayPerSec As Double, _
                    ByVal shape As Integer = 0, ByVal freqEnd As Double = 0)
    Dim As Integer i0 = Int(startSec * b.rate), cnt = Int(durSec * b.rate), k
    Dim As Double ph = 0
    If freqEnd <= 0 Then freqEnd = freq
    For k = 0 To cnt - 1
        Dim As Double t = k / b.rate
        Dim As Double f = freq + (freqEnd - freq) * (k / cnt)
        ph += f / b.rate
        Dim As Double env = Exp(-t * decayPerSec)
        If t < attackSec Then env *= t / attackSec
        '' Short fade-out at the very end avoids clicks.
        Dim As Integer remaining = cnt - k
        If remaining < 64 Then env *= remaining / 64
        Buf_Add(b, i0 + k, amp * env * Wave(shape, ph))
    Next
End Sub

'' Bell: inharmonic partials that die away at different speeds.
Private Sub AddBell(ByRef b As SynthBuffer, ByVal startSec As Double, ByVal freq As Double, ByVal amp As Single, _
                    ByVal durSec As Double = 1.2)
    AddTone(b, startSec, freq, durSec, amp, 0.003, 3.0)
    AddTone(b, startSec, freq * 2.0, durSec * 0.8, amp * 0.45, 0.003, 4.5)
    AddTone(b, startSec, freq * 2.76, durSec * 0.6, amp * 0.25, 0.002, 7.0)
    AddTone(b, startSec, freq * 5.4, durSec * 0.3, amp * 0.12, 0.001, 14.0)
End Sub

'' Plucked string (fast attack, medium decay, soft upper harmonic).
Private Sub AddPluck(ByRef b As SynthBuffer, ByVal startSec As Double, ByVal freq As Double, ByVal amp As Single, _
                     ByVal durSec As Double = 1.5)
    AddTone(b, startSec, freq, durSec, amp, 0.004, 2.6, 1)
    AddTone(b, startSec, freq * 2, durSec * 0.5, amp * 0.3, 0.003, 5.0)
End Sub

'' Wooden knock: filtered noise burst plus two damped resonances.
Dim Shared NoiseSeed As ULong = 22222

Private Function NoiseValue() As Single
    NoiseSeed = NoiseSeed * 1664525UL + 1013904223UL
    Return ((NoiseSeed Shr 8) And &hFFFF) / 32768.0 - 1
End Function

Private Sub AddKnock(ByRef b As SynthBuffer, ByVal startSec As Double, ByVal amp As Single, ByVal pitch As Double)
    Dim As Integer i0 = Int(startSec * b.rate), cnt = Int(0.09 * b.rate), k
    Dim As Single lp = 0
    For k = 0 To cnt - 1
        Dim As Double t = k / b.rate
        lp += (NoiseValue() - lp) * 0.18                   '' one-pole low-pass
        Dim As Double fadeIn = IIf(t < 0.002, t / 0.002, 1.0)      '' avoids a click
        Buf_Add(b, i0 + k, amp * 1.6 * lp * Exp(-t * 75) * fadeIn)
    Next
    AddTone(b, startSec, pitch, 0.12, amp * 0.55, 0.001, 42)
    AddTone(b, startSec, pitch * 2.6, 0.06, amp * 0.25, 0.001, 80)
End Sub

'' Scales the buffer so the loudest sample is at 'peak'.
Private Sub Normalize(ByRef b As SynthBuffer, ByVal peak As Single)
    Dim As Single m = 0
    Dim As Integer i
    For i = 0 To b.n - 1
        If Abs(b.s[i]) > m Then m = Abs(b.s[i])
    Next
    If m < 0.00001 Then Exit Sub
    Dim As Single k = peak / m
    For i = 0 To b.n - 1
        b.s[i] *= k
    Next
End Sub

'' Converts to a 16-bit mono PCM WAV file in memory.
Private Function ToWav(ByRef b As SynthBuffer, ByRef outBuf As UByte Ptr) As Integer
    Dim As Integer dataBytes = b.n * 2, total = 44 + dataBytes
    outBuf = Allocate(total)
    Dim As UByte Ptr p = outBuf
    #macro PUT4CC(off, s)
        p[off] = Asc(s, 1) : p[off + 1] = Asc(s, 2) : p[off + 2] = Asc(s, 3) : p[off + 3] = Asc(s, 4)
    #endmacro
    #macro PUT32(off, v)
        *Cast(ULong Ptr, p + (off)) = CULng(v)
    #endmacro
    #macro PUT16(off, v)
        *Cast(UShort Ptr, p + (off)) = CUShort(v)
    #endmacro
    PUT4CC(0, "RIFF") : PUT32(4, total - 8) : PUT4CC(8, "WAVE")
    PUT4CC(12, "fmt ") : PUT32(16, 16) : PUT16(20, 1) : PUT16(22, 1)
    PUT32(24, b.rate) : PUT32(28, b.rate * 2) : PUT16(32, 2) : PUT16(34, 16)
    PUT4CC(36, "data") : PUT32(40, dataBytes)
    Dim As Short Ptr pcm = Cast(Short Ptr, p + 44)
    Dim As Integer i
    For i = 0 To b.n - 1
        Dim As Single v = b.s[i]
        If v > 1 Then v = 1
        If v < -1 Then v = -1
        pcm[i] = CShort(v * 32767)
    Next
    Return total
End Function

'' Note frequency from a MIDI note number (60 = middle C).
Private Function NoteHz(ByVal midi As Integer) As Double
    Return 440.0 * 2 ^ ((midi - 69) / 12.0)
End Function

Function Audio_SynthesizeWav(ByVal id As Integer, ByRef buffer As UByte Ptr) As Integer
    Dim As SynthBuffer b
    Dim As Integer i
    NoiseSeed = 22222 + id * 777
    Select Case id
    Case SND_MOVE
        Buf_Create(b, SFX_RATE, 0.16)
        AddKnock(b, 0, 0.8, 190)
    Case SND_CAPTURE
        Buf_Create(b, SFX_RATE, 0.26)
        AddKnock(b, 0, 0.9, 170)
        AddKnock(b, 0.075, 1.0, 140)
    Case SND_CASTLE
        Buf_Create(b, SFX_RATE, 0.3)
        AddKnock(b, 0, 0.8, 200)
        AddKnock(b, 0.13, 0.8, 175)
    Case SND_PROMOTE
        Buf_Create(b, SFX_RATE, 0.9)
        AddKnock(b, 0, 0.7, 190)
        AddBell(b, 0.06, NoteHz(79), 0.35, 0.8)
        AddBell(b, 0.16, NoteHz(84), 0.35, 0.7)
    Case SND_CHECK
        Buf_Create(b, SFX_RATE, 0.8)
        AddBell(b, 0, NoteHz(81), 0.45, 0.7)
        AddBell(b, 0.13, NoteHz(86), 0.4, 0.6)
    Case SND_CHECKMATE
        Buf_Create(b, SFX_RATE, 1.6)
        Dim As Integer notes(0 To 3) = {72, 76, 79, 84}
        For i = 0 To 3
            AddBell(b, i * 0.13, NoteHz(notes(i)), 0.35, 1.2)
        Next
    Case SND_ILLEGAL
        Buf_Create(b, SFX_RATE, 0.22)
        AddTone(b, 0, 160, 0.2, 0.6, 0.003, 14, 2, 105)
        AddTone(b, 0, 320, 0.1, 0.15, 0.003, 30, 0)
    Case SND_CLICK
        Buf_Create(b, SFX_RATE, 0.04)
        AddTone(b, 0, 1900, 0.035, 0.5, 0.0005, 160)
        AddTone(b, 0, 950, 0.03, 0.25, 0.0005, 180)
    Case SND_VICTORY
        Buf_Create(b, SFX_RATE, 2.0)
        '' Little fanfare: G C E G ... C (C major)
        Dim As Integer mel(0 To 4) = {67, 72, 76, 79, 84}
        Dim As Double tm(0 To 4) = {0, 0.14, 0.28, 0.42, 0.62}
        For i = 0 To 4
            AddTone(b, tm(i), NoteHz(mel(i)), IIf(i = 4, 1.3, 0.3), 0.32, 0.01, IIf(i = 4, 1.6, 4.0), 1)
            AddTone(b, tm(i), NoteHz(mel(i)) * 2, IIf(i = 4, 1.0, 0.25), 0.08, 0.01, 5.0, 0)
        Next
        AddTone(b, 0.62, NoteHz(76), 1.2, 0.18, 0.02, 1.8, 1)
        AddTone(b, 0.62, NoteHz(79), 1.2, 0.16, 0.02, 1.8, 1)
        AddTone(b, 0.62, NoteHz(48), 1.2, 0.25, 0.02, 1.5, 0)
    Case SND_DEFEAT
        Buf_Create(b, SFX_RATE, 1.8)
        '' Gentle, a little sad - but not scary.
        Dim As Integer mel(0 To 3) = {76, 74, 72, 69}
        For i = 0 To 3
            AddTone(b, i * 0.28, NoteHz(mel(i)), 0.9, 0.3, 0.03, 2.5, 1)
        Next
        AddTone(b, 0.84, NoteHz(57), 0.9, 0.2, 0.05, 2.0, 0)
    Case SND_DRAW
        Buf_Create(b, SFX_RATE, 1.2)
        AddPluck(b, 0, NoteHz(72), 0.4, 1.0)
        AddPluck(b, 0.2, NoteHz(67), 0.4, 1.0)
    Case SND_SOLVED
        Buf_Create(b, SFX_RATE, 1.3)
        Dim As Integer notes(0 To 5) = {84, 86, 88, 91, 93, 96}
        For i = 0 To 5
            AddBell(b, i * 0.07, NoteHz(notes(i)), 0.22, 0.9)
        Next
    Case SND_START
        Buf_Create(b, SFX_RATE, 1.0)
        AddBell(b, 0, NoteHz(79), 0.35, 0.9)
        AddBell(b, 0.15, NoteHz(84), 0.35, 0.8)
    Case Else
        Buf_Create(b, SFX_RATE, 0.05)
    End Select
    Normalize(b, 0.85)
    Dim As Integer size = ToWav(b, buffer)
    Buf_Free(b)
    Return size
End Function

'' A calm, seamless 8-bar loop: pad chords, bass, plucked arpeggios and a
'' pentatonic melody over C - Am - F - G (twice, second time varied).
Function Audio_SynthesizeMusic(ByRef buffer As UByte Ptr) As Integer
    Const BEAT = 60.0 / 76
    Dim As Integer bars = 8
    Dim As SynthBuffer b
    Buf_Create(b, MUSIC_RATE, bars * 4 * BEAT, True)
    Dim As Integer chordRoot(0 To 3) = {48, 45, 41, 43}        '' C, A, F, G
    Dim As Integer chordThird(0 To 3) = {4, 3, 4, 4}
    Dim As Integer penta(0 To 9) = {72, 74, 76, 79, 81, 84, 86, 88, 91, 93}
    Dim As ULong rng = 12345
    Dim As Integer bar, k, last = 4
    For bar = 0 To bars - 1
        Dim As Integer c = bar Mod 4
        Dim As Double t0 = bar * 4 * BEAT
        Dim As Integer root = chordRoot(c), third = root + chordThird(c), fifth = root + 7
        '' Pad (soft triangle chord, slow attack)
        AddTone(b, t0, NoteHz(root + 12), 4.6 * BEAT, 0.06, 0.6, 0.35, 1)
        AddTone(b, t0, NoteHz(third + 12), 4.6 * BEAT, 0.05, 0.7, 0.35, 1)
        AddTone(b, t0, NoteHz(fifth + 12), 4.6 * BEAT, 0.05, 0.8, 0.35, 1)
        '' Bass on beats 1 and 3
        AddTone(b, t0, NoteHz(root - 12), 2 * BEAT, 0.16, 0.02, 1.4, 0)
        AddTone(b, t0 + 2 * BEAT, NoteHz(root - 12 + IIf(bar Mod 2 = 1, 7, 0)), 2 * BEAT, 0.13, 0.02, 1.4, 0)
        '' Arpeggio in eighth notes
        Dim As Integer arp(0 To 7) = {root + 12, third + 12, fifth + 12, root + 24, fifth + 12, third + 12, fifth + 12, root + 24}
        For k = 0 To 7
            AddPluck(b, t0 + k * BEAT / 2, NoteHz(arp(k)), 0.06, 1.2)
        Next
        '' Melody: a few notes per bar, moving by small steps (sounds sung).
        Dim As Integer notesInBar = IIf(bar Mod 4 = 3, 2, 3)
        For k = 0 To notesInBar - 1
            rng = rng * 1103515245UL + 12345UL
            Dim As Integer stepV = CInt((rng Shr 16) Mod 5) - 2
            If bar >= 4 AndAlso k = 0 Then stepV += 1          '' variation the second time
            last += stepV
            If last < 0 Then last = 1
            If last > 9 Then last = 8
            Dim As Double tn = t0 + k * (4 * BEAT / notesInBar)
            AddBell(b, tn, NoteHz(penta(last)), 0.07, 1.6)
            AddTone(b, tn, NoteHz(penta(last)), 1.2, 0.05, 0.05, 1.2, 1)
        Next
    Next
    Normalize(b, 0.7)
    Dim As Integer size = ToWav(b, buffer)
    Buf_Free(b)
    Return size
End Function

'' =====================================================================
'' BASS loading and playback
'' =====================================================================
Private Function LoadBass() As Boolean
    Dim As String candidates(0 To 3)
#ifdef __FB_WIN32__
    candidates(0) = ExePath() & "\bass.dll" : candidates(1) = "bass.dll"
    candidates(2) = "bass" : candidates(3) = ""
#else
    candidates(0) = ExePath() & "/libbass.so" : candidates(1) = "libbass.so"
    candidates(2) = "/usr/local/lib/libbass.so" : candidates(3) = "bass"
#endif
    '' BEGINNERCHESS_BASS=<file> forces a specific library file (for testing).
    If Environ("BEGINNERCHESS_BASS") <> "" Then
        candidates(0) = Environ("BEGINNERCHESS_BASS")
        candidates(1) = "" : candidates(2) = "" : candidates(3) = ""
    End If
    Dim As Integer i
    For i = 0 To 3
        If candidates(i) = "" Then Continue For
        BassLib = DyLibLoad(candidates(i))
        If BassLib Then Exit For
    Next
    If BassLib = 0 Then
        AudioStatus = "No sound: the BASS library (" & BASS_FILE_NAME & ") was not found."
        Return False
    End If
    pBASS_Init = DyLibSymbol(BassLib, "BASS_Init")
    pBASS_Free = DyLibSymbol(BassLib, "BASS_Free")
    pBASS_GetVersion = DyLibSymbol(BassLib, "BASS_GetVersion")
    pBASS_ErrorGetCode = DyLibSymbol(BassLib, "BASS_ErrorGetCode")
    pBASS_SampleLoad = DyLibSymbol(BassLib, "BASS_SampleLoad")
    pBASS_SampleGetChannel = DyLibSymbol(BassLib, "BASS_SampleGetChannel")
    pBASS_StreamCreateFile = DyLibSymbol(BassLib, "BASS_StreamCreateFile")
    pBASS_StreamFree = DyLibSymbol(BassLib, "BASS_StreamFree")
    pBASS_ChannelPlay = DyLibSymbol(BassLib, "BASS_ChannelPlay")
    pBASS_ChannelStop = DyLibSymbol(BassLib, "BASS_ChannelStop")
    pBASS_ChannelSetAttribute = DyLibSymbol(BassLib, "BASS_ChannelSetAttribute")
    pBASS_ChannelIsActive = DyLibSymbol(BassLib, "BASS_ChannelIsActive")
    If pBASS_Init = 0 OrElse pBASS_Free = 0 OrElse pBASS_GetVersion = 0 OrElse pBASS_ErrorGetCode = 0 _
       OrElse pBASS_SampleLoad = 0 OrElse pBASS_SampleGetChannel = 0 OrElse pBASS_StreamCreateFile = 0 _
       OrElse pBASS_StreamFree = 0 OrElse pBASS_ChannelPlay = 0 OrElse pBASS_ChannelStop = 0 _
       OrElse pBASS_ChannelSetAttribute = 0 OrElse pBASS_ChannelIsActive = 0 Then
        AudioStatus = "No sound: the BASS library is incomplete or too old."
        DyLibFree BassLib
        BassLib = 0
        Return False
    End If
    Return True
End Function

Private Function VersionText(ByVal v As ULong) As String
    Return ((v Shr 24) And 255) & "." & ((v Shr 16) And 255) & "." & ((v Shr 8) And 255)
End Function

'' Loads a user-supplied effect file if one exists.
Private Function LoadOverride(ByVal id As Integer) As ULong
    Dim As String exts(0 To 2) = {".wav", ".ogg", ".mp3"}
    Dim As Integer i
    For i = 0 To 2
        Dim As String fn = AudioBase & "/sound/effects/" & Audio_SoundName(id) & exts(i)
        If FileExists(fn) Then
            Dim As ULong h = pBASS_SampleLoad(0, StrPtr(fn), 0, 0, 4, BASS_SAMPLE_OVER_POS)
            If h Then Return h
        End If
    Next
    Return 0
End Function

Private Sub ScanMusicFolder()
    MusicFileCount = 0
    Dim As String exts(0 To 5) = {"*.ogg", "*.mp3", "*.wav", "*.OGG", "*.MP3", "*.WAV"}
    Dim As Integer i
    For i = 0 To 5
        Dim As String f = Dir(AudioBase & "/sound/music/" & exts(i), fbNormal)
        Do While f <> "" AndAlso MusicFileCount < 64
            MusicFiles(MusicFileCount) = AudioBase & "/sound/music/" & f
            MusicFileCount += 1
            f = Dir()
        Loop
    Next
End Sub

Function Audio_Init(ByRef baseDir As Const String) As Boolean
    If AudioReady Then Return True
    AudioBase = baseDir
    If Environ("BEGINNERCHESS_NOSOUND") <> "" Then
        AudioStatus = "Sound is switched off (BEGINNERCHESS_NOSOUND is set)."
        Return False
    End If
    If Not LoadBass() Then Return False
    If pBASS_Init(-1, 44100, 0, 0, 0) = 0 Then
        Dim As Long e = pBASS_ErrorGetCode()
        If e <> BASS_ERROR_ALREADY Then
            AudioStatus = "No sound: no working sound device was found (BASS error " & e & ")."
            DyLibFree BassLib
            BassLib = 0
            Return False
        End If
    End If
    Dim As Integer id
    For id = 0 To SND_COUNT - 1
        SampleHandle(id) = LoadOverride(id)
        If SampleHandle(id) = 0 Then
            Dim As Integer size = Audio_SynthesizeWav(id, SampleData(id))
            SampleHandle(id) = pBASS_SampleLoad(1, SampleData(id), 0, size, 4, BASS_SAMPLE_OVER_POS)
        End If
    Next
    ScanMusicFolder()
    AudioReady = True
    AudioStatus = "BASS " & VersionText(pBASS_GetVersion()) & " - sound ready" & _
                  IIf(MusicFileCount > 0, " (" & MusicFileCount & " music files)", "")
    Return True
End Function

Function Audio_Available() As Boolean
    Return AudioReady
End Function

Function Audio_StatusText() As String
    If AudioStatus = "" Then Return "Sound has not been started."
    Return AudioStatus
End Function

Sub Audio_Play(ByVal id As Integer)
    If Not AudioReady OrElse Not SoundOn OrElse id < 0 OrElse id >= SND_COUNT Then Exit Sub
    If SampleHandle(id) = 0 Then Exit Sub
    Dim As ULong ch = pBASS_SampleGetChannel(SampleHandle(id), 0)
    If ch = 0 Then Exit Sub
    pBASS_ChannelSetAttribute(ch, BASS_ATTRIB_VOL, SoundVol)
    pBASS_ChannelPlay(ch, 0)
End Sub

Sub Audio_SetSound(ByVal enabled As Boolean, ByVal volume As Integer)
    SoundOn = enabled
    SoundVol = IIf(volume < 0, 0, IIf(volume > 100, 100, volume)) / 100.0
End Sub

Private Sub StopMusic()
    If MusicStream Then
        pBASS_ChannelStop(MusicStream)
        pBASS_StreamFree(MusicStream)
        MusicStream = 0
    End If
End Sub

Private Sub StartMusic()
    StopMusic()
    If MusicFileCount > 0 Then
        '' Play the user's files one after another.
        Dim As Integer tries
        For tries = 1 To MusicFileCount
            Dim As String fn = MusicFiles(MusicIndex Mod MusicFileCount)
            MusicIndex += 1
            MusicStream = pBASS_StreamCreateFile(0, StrPtr(fn), 0, 0, 0)
            If MusicStream Then Exit For
        Next
    End If
    If MusicStream = 0 Then
        If MusicData = 0 Then MusicSize = Audio_SynthesizeMusic(MusicData)
        MusicStream = pBASS_StreamCreateFile(1, MusicData, 0, MusicSize, BASS_SAMPLE_LOOP)
    End If
    If MusicStream Then
        pBASS_ChannelSetAttribute(MusicStream, BASS_ATTRIB_VOL, MusicVol)
        pBASS_ChannelPlay(MusicStream, 0)
    End If
End Sub

Sub Audio_SetMusic(ByVal enabled As Boolean, ByVal volume As Integer)
    MusicVol = IIf(volume < 0, 0, IIf(volume > 100, 100, volume)) / 100.0
    If Not AudioReady Then
        MusicOn = enabled
        Exit Sub
    End If
    If enabled AndAlso Not MusicOn Then
        MusicOn = True
        StartMusic()
    ElseIf (Not enabled) AndAlso MusicOn Then
        MusicOn = False
        StopMusic()
    ElseIf MusicStream Then
        pBASS_ChannelSetAttribute(MusicStream, BASS_ATTRIB_VOL, MusicVol)
    End If
End Sub

Sub Audio_Update()
    If Not AudioReady OrElse Not MusicOn Then Exit Sub
    '' A user's music file finished: start the next one.
    If MusicStream = 0 OrElse pBASS_ChannelIsActive(MusicStream) = BASS_ACTIVE_STOPPED Then StartMusic()
End Sub

Sub Audio_Shutdown()
    If AudioReady Then
        StopMusic()
        pBASS_Free()
        AudioReady = False
    End If
    If BassLib Then DyLibFree BassLib : BassLib = 0
    Dim As Integer i
    For i = 0 To SND_COUNT - 1
        If SampleData(i) Then Deallocate SampleData(i) : SampleData(i) = 0
        SampleHandle(i) = 0
    Next
    If MusicData Then Deallocate MusicData : MusicData = 0
End Sub
