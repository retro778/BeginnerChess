'' =====================================================================
'' BeginnerChess - tests/test_tokenstore.bas
'' The "remember me" token store (DPAPI on Windows, 0600 file on Linux).
'' =====================================================================
#include once "../modules/tokenstore.bi"
#include once "testutil.bi"

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

Function FileText(ByRef fileName As Const String) As String
    Dim As Integer f = FreeFile
    If Open(fileName For Binary Access Read As #f) <> 0 Then Return ""
    Dim As String s = Space(Lof(f))
    Get #f, , s
    Close #f
    Return s
End Function

Print "BeginnerChess token store tests"
Dim As String folder = Test_TempDir("bc_token_test")
Test_RemoveTree(folder)
Token_SetFolder(folder)
Dim As String token = "kQ3_xY-9abcdefghijklmnopqrstuvwxyz0123456789AB"
Check Token_Load("freedomnet.tech") = "", "nothing stored yet"
Check Token_Save("freedomnet.tech", token), "token saved"
Check Token_Load("freedomnet.tech") = token, "token read back"
Check Token_Load("other.example") = "", "tokens belong to one server"
Dim As String fileName = folder & "/online-freedomnet.tech.token"
Check FileExists(fileName), "token file exists", fileName
Check InStr(FileText(fileName), token) = 0, "the file does not contain the token as plain text"
#ifndef __FB_WIN32__
    Dim As Integer f = FreeFile
    Dim As String modeText
    If Open Pipe("stat -c %a " & fileName For Input As #f) = 0 Then
        Line Input #f, modeText
        Close #f
    End If
    Check modeText = "600", "file readable only by the user", modeText
    f = FreeFile
    If Open Pipe("stat -c %a " & folder For Input As #f) = 0 Then
        Line Input #f, modeText
        Close #f
    End If
    Check modeText = "700", "folder private", modeText
#endif
Check Token_Save("freedomnet.tech", "second-token-0123456789012345678901"), "replace"
Check Token_Load("freedomnet.tech") = "second-token-0123456789012345678901", "replaced token read"
Token_Delete("freedomnet.tech")
Check Not FileExists(fileName) AndAlso Token_Load("freedomnet.tech") = "", "deleted"
'' A damaged file is ignored, not trusted.
Dim As Integer g = FreeFile
Open fileName For Output As #g
Print #g, "garbage that is not a token"
Close #g
Check Token_Load("freedomnet.tech") = "", "damaged file ignored"
Check Token_Save("weird host/../x", "abcdefghijklmnopqrstu"), "odd server names are made safe"
Check Token_Load("weird host/../x") = "abcdefghijklmnopqrstu", "and read back"
Test_RemoveTree(folder)
Print
Print "Passed: " & TestsPassed & "   Failed: " & TestsFailed
If TestsFailed > 0 Then End 1
End 0
