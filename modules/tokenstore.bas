'' =====================================================================
'' BeginnerChess - tokenstore.bas
'' Safe storage of the "remember me" session token. See tokenstore.bi.
'' =====================================================================
#include once "tokenstore.bi"
#include once "file.bi"
#include once "dir.bi"

Dim Shared TokenFolderOverride As String

Sub Token_SetFolder(ByRef folder As Const String)
    TokenFolderOverride = folder
End Sub

Private Function SafeName(ByRef serverHost As Const String) As String
    Dim As String r
    Dim As Integer k
    For k = 0 To Len(serverHost) - 1
        Dim As Integer c = serverHost[k]
        If (c >= 48 AndAlso c <= 57) OrElse (c >= 65 AndAlso c <= 90) OrElse (c >= 97 AndAlso c <= 122) _
           OrElse c = 45 OrElse c = 46 Then r &= Chr(c) Else r &= "_"
    Next
    If r = "" Then r = "server"
    Return Left(r, 80)
End Function

Private Function ToHex(ByRef s As Const String) As String
    Dim As String r
    Dim As Integer k
    For k = 0 To Len(s) - 1
        r &= Hex(s[k], 2)
    Next
    Return r
End Function

Private Function FromHex(ByRef h As Const String) As String
    Dim As String r
    Dim As Integer k
    For k = 1 To Len(h) - 1 Step 2
        Dim As String pair = Mid(h, k, 2)
        If pair <> Hex(ValInt("&h" & pair), 2) Then Return ""        '' not hex
        r &= Chr(ValInt("&h" & pair))
    Next
    Return r
End Function

Private Function ReadAll(ByRef fileName As Const String) As String
    If Not FileExists(fileName) Then Return ""
    Dim As Integer f = FreeFile
    If Open(fileName For Binary Access Read As #f) <> 0 Then Return ""
    Dim As LongInt n = Lof(f)
    Dim As String s
    If n > 0 AndAlso n < 65536 Then
        s = Space(n)
        Get #f, , s
    End If
    Close #f
    Return s
End Function

#ifdef __FB_WIN32__
'' ---------------------------------------------------------------------
'' Windows: DPAPI
'' ---------------------------------------------------------------------
Type DataBlob
    cbData As ULong
    pbData As UByte Ptr
End Type
Type CP_Protect As Function Stdcall (ByVal dataIn As DataBlob Ptr, ByVal descr As WString Ptr, _
                                     ByVal entropy As DataBlob Ptr, ByVal reserved As Any Ptr, _
                                     ByVal prompt As Any Ptr, ByVal flags As ULong, ByVal dataOut As DataBlob Ptr) As Long
Type CP_Unprotect As Function Stdcall (ByVal dataIn As DataBlob Ptr, ByVal descr As Any Ptr, _
                                       ByVal entropy As DataBlob Ptr, ByVal reserved As Any Ptr, _
                                       ByVal prompt As Any Ptr, ByVal flags As ULong, ByVal dataOut As DataBlob Ptr) As Long
Type K32_LocalFree As Function Stdcall (ByVal p As Any Ptr) As Any Ptr
Const CRYPTPROTECT_UI_FORBIDDEN = 1

Dim Shared hCrypt As Any Ptr, hK32 As Any Ptr
Dim Shared pProtect As CP_Protect, pUnprotect As CP_Unprotect, pLocalFree As K32_LocalFree

Private Function LoadDpapi() As Boolean
    If pProtect <> 0 Then Return True
    hCrypt = DyLibLoad("crypt32.dll")
    hK32 = DyLibLoad("kernel32.dll")
    If hCrypt = 0 OrElse hK32 = 0 Then Return False
    pProtect = DyLibSymbol(hCrypt, "CryptProtectData")
    pUnprotect = DyLibSymbol(hCrypt, "CryptUnprotectData")
    pLocalFree = DyLibSymbol(hK32, "LocalFree")
    Return pProtect <> 0 AndAlso pUnprotect <> 0 AndAlso pLocalFree <> 0
End Function

'' Encrypts (protect = True) or decrypts s for the current Windows user.
Private Function Dpapi(ByRef s As Const String, ByVal protect As Boolean, ByRef ok As Boolean) As String
    ok = False
    If Not LoadDpapi() OrElse Len(s) = 0 Then Return ""
    Dim As DataBlob inBlob, outBlob
    Dim As String buf = s
    inBlob.cbData = Len(buf)
    inBlob.pbData = Cast(UByte Ptr, StrPtr(buf))
    Dim As WString * 16 descr = "BeginnerChess"
    Dim As Long r
    If protect Then
        r = pProtect(@inBlob, @descr, 0, 0, 0, CRYPTPROTECT_UI_FORBIDDEN, @outBlob)
    Else
        r = pUnprotect(@inBlob, 0, 0, 0, 0, CRYPTPROTECT_UI_FORBIDDEN, @outBlob)
    End If
    If r = 0 OrElse outBlob.pbData = 0 Then Return ""
    Dim As String result = Space(outBlob.cbData)
    Dim As ULong k
    For k = 0 To outBlob.cbData - 1
        result[k] = outBlob.pbData[k]
    Next
    pLocalFree(outBlob.pbData)
    ok = True
    Return result
End Function

Function Token_Folder() As String
    If TokenFolderOverride <> "" Then Return TokenFolderOverride
    Dim As String home = Environ("APPDATA")
    If home = "" Then home = Environ("USERPROFILE")
    Return home & "\BeginnerChess"
End Function

Private Function TokenFile(ByRef serverHost As Const String) As String
    Return Token_Folder() & "\online-" & SafeName(serverHost) & ".token"
End Function

Function Token_Save(ByRef serverHost As Const String, ByRef token As Const String) As Boolean
    Dim As Boolean ok
    Dim As String enc = Dpapi(token, True, ok)
    If Not ok Then Return False
    Dim As String folder = Token_Folder()
    If Dir(folder, fbDirectory) = "" Then MkDir folder
    Dim As Integer f = FreeFile
    If Open(TokenFile(serverHost) For Output As #f) <> 0 Then Return False
    Print #f, "DPAPI " & ToHex(enc)
    Close #f
    Return True
End Function

Function Token_Load(ByRef serverHost As Const String) As String
    Dim As String s = Trim(ReadAll(TokenFile(serverHost)), Any Chr(13, 10, 32))
    If Left(s, 6) <> "DPAPI " Then Return ""
    Dim As Boolean ok
    Dim As String token = Dpapi(FromHex(Mid(s, 7)), False, ok)
    Return IIf(ok, token, "")
End Function

#else
'' ---------------------------------------------------------------------
'' Linux / Unix: a file only the user can read
'' ---------------------------------------------------------------------
Declare Function c_chmod Cdecl Alias "chmod" (ByVal path As ZString Ptr, ByVal mode As ULong) As Long

Function Token_Folder() As String
    If TokenFolderOverride <> "" Then Return TokenFolderOverride
    Dim As String home = Environ("HOME")
    If home = "" Then home = "/tmp"
    Return home & "/.beginnerchess"
End Function

Private Function TokenFile(ByRef serverHost As Const String) As String
    Return Token_Folder() & "/online-" & SafeName(serverHost) & ".token"
End Function

Function Token_Save(ByRef serverHost As Const String, ByRef token As Const String) As Boolean
    Dim As String folder = Token_Folder()
    If Dir(folder, fbDirectory) = "" Then MkDir folder
    c_chmod(StrPtr(folder), &o700)
    Dim As String fileName = TokenFile(serverHost)
    '' Create the file empty, restrict it, and only then write the token.
    Dim As Integer f = FreeFile
    If Open(fileName For Output As #f) <> 0 Then Return False
    Close #f
    If c_chmod(StrPtr(fileName), &o600) <> 0 Then
        Kill fileName
        Return False
    End If
    f = FreeFile
    If Open(fileName For Output As #f) <> 0 Then Return False
    Print #f, "PLAIN " & ToHex(token)
    Close #f
    Return True
End Function

Function Token_Load(ByRef serverHost As Const String) As String
    Dim As String s = Trim(ReadAll(TokenFile(serverHost)), Any Chr(13, 10, 32))
    If Left(s, 6) <> "PLAIN " Then Return ""
    Return FromHex(Mid(s, 7))
End Function
#endif

Sub Token_Delete(ByRef serverHost As Const String)
    Dim As String fileName = TokenFile(serverHost)
    If FileExists(fileName) Then
        '' Overwrite before deleting (the token is short; this is cheap).
        Dim As Integer f = FreeFile
        If Open(fileName For Output As #f) = 0 Then
            Print #f, String(120, "0")
            Close #f
        End If
        Kill fileName
    End If
End Sub
