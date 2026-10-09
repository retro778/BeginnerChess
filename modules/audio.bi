'' =====================================================================
'' BeginnerChess - audio.bi
'' Sound effects and background music through the BASS audio library.
''
'' * BASS is loaded at run time (DyLibLoad), not linked: if libbass.so /
''   bass.dll is missing or no sound device works, BeginnerChess simply runs
''   silently.
'' * All built-in sounds and the background music are synthesised by the
''   program itself (original, no licensing questions).
'' * Optional overrides: sound/effects/<name>.wav|.ogg|.mp3 replaces a
''   built-in effect; audio files in sound/music/ are played instead of
''   the built-in music.
'' =====================================================================
#pragma once

Enum SoundId
    SND_MOVE = 0
    SND_CAPTURE
    SND_CASTLE
    SND_PROMOTE
    SND_CHECK
    SND_CHECKMATE
    SND_ILLEGAL
    SND_CLICK
    SND_VICTORY
    SND_DEFEAT
    SND_DRAW
    SND_SOLVED
    SND_START
    SND_COUNT
End Enum

'' Starts audio. baseDir = folder containing sound/ (normally ExePath).
'' Returns False (and keeps working silently) if audio is unavailable.
Declare Function Audio_Init(ByRef baseDir As Const String) As Boolean
Declare Sub Audio_Shutdown()
Declare Function Audio_Available() As Boolean
'' Human-readable status, e.g. "BASS 2.4.17 - sound ready".
Declare Function Audio_StatusText() As String

Declare Sub Audio_Play(ByVal id As Integer)
Declare Sub Audio_SetSound(ByVal enabled As Boolean, ByVal volume As Integer)
Declare Sub Audio_SetMusic(ByVal enabled As Boolean, ByVal volume As Integer)
'' Call once per frame (advances the music playlist).
Declare Sub Audio_Update()

Declare Function Audio_SoundName(ByVal id As Integer) As String
'' Synthesises a built-in sound as a complete WAV file in memory.
'' Returns its size in bytes (the caller owns the returned buffer).
Declare Function Audio_SynthesizeWav(ByVal id As Integer, ByRef buffer As UByte Ptr) As Integer
'' Synthesises the built-in background music loop as a WAV file.
Declare Function Audio_SynthesizeMusic(ByRef buffer As UByte Ptr) As Integer
