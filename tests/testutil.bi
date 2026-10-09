'' =====================================================================
'' BeginnerChess - tests/testutil.bi
'' Small file helpers for the test programs that work the same on Linux
'' and Windows (no shell commands such as rm, cp or mkdir -p).
'' =====================================================================
#pragma once
#include once "dir.bi"
#include once "file.bi"

'' A folder for temporary test files: $TEMP (Windows) or /tmp (Linux).
Function Test_TempDir(ByRef subName As Const String) As String
#ifdef __FB_WIN32__
    Dim As String base0 = Environ("TEMP")
    If base0 = "" Then base0 = Environ("TMP")
    If base0 = "" Then base0 = ExePath()
    Return base0 & "\" & subName
#else
    Return "/tmp/" & subName
#endif
End Function

'' Deletes a folder with everything in it (no error if it does not exist).
Sub Test_RemoveTree(ByRef folder As Const String)
    If Dir(folder, fbDirectory) = "" Then Exit Sub
    '' Collect the names first: Dir() cannot be used recursively.
    Dim As String names(), entry
    Dim As Integer n = 0, i, attr
    entry = Dir(folder & "/*", fbNormal Or fbHidden Or fbSystem Or fbDirectory, attr)
    Do While entry <> ""
        If entry <> "." AndAlso entry <> ".." Then
            ReDim Preserve names(0 To n)
            names(n) = IIf((attr And fbDirectory) <> 0, "D", "F") & entry
            n += 1
        End If
        entry = Dir(attr)
    Loop
    For i = 0 To n - 1
        Dim As String full = folder & "/" & Mid(names(i), 2)
        If Left(names(i), 1) = "D" Then Test_RemoveTree(full) Else Kill full
    Next
    RmDir folder
End Sub

'' Creates a folder and any missing parent folders.
Sub Test_MakeDirs(ByRef folder As Const String)
    If folder = "" OrElse Dir(folder, fbDirectory) <> "" Then Exit Sub
    Dim As Integer i
    For i = Len(folder) To 2 Step -1
        Dim As String ch = Mid(folder, i, 1)
        If ch = "/" OrElse ch = "\" Then
            Test_MakeDirs(Left(folder, i - 1))
            Exit For
        End If
    Next
    MkDir folder
End Sub

'' Copies one file; True on success.
Function Test_CopyFile(ByRef source As Const String, ByRef target As Const String) As Boolean
    Return FileCopy(source, target) = 0       '' FileCopy returns 0 on success
End Function
