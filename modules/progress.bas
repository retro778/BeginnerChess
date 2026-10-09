'' =====================================================================
'' BeginnerChess - progress.bas
'' See progress.bi.
'' =====================================================================
#include once "progress.bi"
#include once "file.bi"

Dim Shared ProgFile As String
Dim Shared ProgKeys() As String
Dim Shared ProgValues() As String
Dim Shared ProgCount As Integer = 0

Sub Progress_SetFile(ByRef fileName As Const String)
    ProgFile = fileName
End Sub

Sub Progress_Clear()
    Erase ProgKeys
    Erase ProgValues
    ProgCount = 0
End Sub

Private Function FindKey(ByRef key As Const String) As Integer
    Dim As Integer i
    For i = 0 To ProgCount - 1
        If ProgKeys(i) = key Then Return i
    Next
    Return -1
End Function

Function Progress_GetValue(ByRef key As Const String, ByRef def As Const String = "") As String
    Dim As Integer i = FindKey(key)
    If i < 0 Then Return def
    Return ProgValues(i)
End Function

Sub Progress_SetValue(ByRef key As Const String, ByRef value As Const String)
    Dim As Integer i = FindKey(key)
    If i < 0 Then
        If ProgCount = 0 Then
            ReDim ProgKeys(0 To 63)
            ReDim ProgValues(0 To 63)
        ElseIf ProgCount > UBound(ProgKeys) Then
            ReDim Preserve ProgKeys(0 To ProgCount * 2)
            ReDim Preserve ProgValues(0 To ProgCount * 2)
        End If
        i = ProgCount
        ProgKeys(i) = key
        ProgCount += 1
    End If
    ProgValues(i) = value
End Sub

Function Progress_Load() As Boolean
    Progress_Clear()
    Dim As Integer f = FreeFile
    If ProgFile = "" OrElse Open(ProgFile For Input As #f) <> 0 Then Return False
    Dim As String ln
    Do While Not EOF(f)
        Line Input #f, ln
        ln = Trim(ln, Any " " & Chr(9, 13))
        If ln = "" OrElse Left(ln, 1) = "#" Then Continue Do
        Dim As Integer eq = InStr(ln, "=")
        If eq > 1 Then Progress_SetValue(Trim(Left(ln, eq - 1)), Trim(Mid(ln, eq + 1)))
    Loop
    Close #f
    Return True
End Function

Function Progress_Save() As Boolean
    If ProgFile = "" Then Return False
    Dim As String tmp = ProgFile & ".tmp"
    Dim As Integer f = FreeFile, i
    If Open(tmp For Output As #f) <> 0 Then Return False
    Print #f, "# Beginner Chess progress"
    For i = 0 To ProgCount - 1
        Print #f, ProgKeys(i) & "=" & ProgValues(i)
    Next
    Close #f
    If FileExists(ProgFile) Then Kill ProgFile
    Return Name(tmp, ProgFile) = 0
End Function

Function Progress_IsLessonDone(ByRef id As Const String) As Boolean
    Return Progress_GetValue("lesson." & id) = "1"
End Function

Sub Progress_SetLessonDone(ByRef id As Const String)
    Progress_SetValue("lesson." & id, "1")
End Sub

Function Progress_IsPuzzleSolved(ByRef id As Const String) As Boolean
    Return Progress_GetValue("puzzle." & id) = "1"
End Function

Sub Progress_SetPuzzleSolved(ByRef id As Const String)
    Progress_SetValue("puzzle." & id, "1")
End Sub

Sub Progress_AddPuzzleAttempt(ByRef id As Const String)
    Progress_SetValue("tries." & id, Str(Progress_PuzzleAttempts(id) + 1))
End Sub

Function Progress_PuzzleAttempts(ByRef id As Const String) As Integer
    Return ValInt(Progress_GetValue("tries." & id, "0"))
End Function

Private Function CountPrefix(ByRef prefix As Const String, ByRef needValue As Const String) As Integer
    Dim As Integer i, n = 0
    For i = 0 To ProgCount - 1
        If Left(ProgKeys(i), Len(prefix)) = prefix Then
            If needValue = "" OrElse ProgValues(i) = needValue Then n += 1
        End If
    Next
    Return n
End Function

Function Progress_LessonsDone() As Integer
    Return CountPrefix("lesson.", "1")
End Function

Function Progress_PuzzlesSolved() As Integer
    Return CountPrefix("puzzle.", "1")
End Function

Function Progress_PuzzlesAttempted() As Integer
    Return CountPrefix("tries.", "")
End Function
