'' =====================================================================
'' BeginnerChess - progress.bi
'' What the player has achieved in Learn Chess and Chess Puzzles:
'' completed lessons, solved and attempted puzzles. Stored as a small
'' "key=value" file (progress.ini) in the data folder. Phase 8 builds the
'' player profile and statistics on top of this.
'' =====================================================================
#pragma once

Declare Sub Progress_SetFile(ByRef fileName As Const String)
Declare Function Progress_Load() As Boolean
Declare Function Progress_Save() As Boolean

Declare Function Progress_IsLessonDone(ByRef id As Const String) As Boolean
Declare Sub Progress_SetLessonDone(ByRef id As Const String)
Declare Function Progress_IsPuzzleSolved(ByRef id As Const String) As Boolean
Declare Sub Progress_SetPuzzleSolved(ByRef id As Const String)
Declare Sub Progress_AddPuzzleAttempt(ByRef id As Const String)
Declare Function Progress_PuzzleAttempts(ByRef id As Const String) As Integer

Declare Function Progress_LessonsDone() As Integer
Declare Function Progress_PuzzlesSolved() As Integer
Declare Function Progress_PuzzlesAttempted() As Integer

'' Generic counters/values for later phases (statistics, achievements).
Declare Function Progress_GetValue(ByRef key As Const String, ByRef def As Const String = "") As String
Declare Sub Progress_SetValue(ByRef key As Const String, ByRef value As Const String)
Declare Sub Progress_Clear()
