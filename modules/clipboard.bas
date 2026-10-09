'' =====================================================================
'' BeginnerChess - clipboard.bas
'' See clipboard.bi. The Windows headers are included only here so that
'' their many names do not clash with the rest of the program.
'' =====================================================================
#include once "clipboard.bi"

#ifdef __FB_WIN32__
#include once "windows.bi"

Function Clipboard_SetText(ByRef text As Const String) As Boolean
    If OpenClipboard(0) = 0 Then Return False
    EmptyClipboard()
    Dim As HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, Len(text) + 1)
    If h = 0 Then
        CloseClipboard()
        Return False
    End If
    Dim As ZString Ptr dst = GlobalLock(h)
    If dst = 0 Then
        CloseClipboard()
        Return False
    End If
    *dst = text
    GlobalUnlock(h)
    Dim As Boolean ok = (SetClipboardData(CF_TEXT, h) <> 0)
    CloseClipboard()
    Return ok
End Function

Function Clipboard_GetText(ByRef text As String) As Boolean
    text = ""
    If OpenClipboard(0) = 0 Then Return False
    Dim As HANDLE h = GetClipboardData(CF_TEXT)
    Dim As Boolean ok = False
    If h <> 0 Then
        Dim As ZString Ptr src = GlobalLock(h)
        If src <> 0 Then
            text = *src
            GlobalUnlock(h)
            ok = True
        End If
    End If
    CloseClipboard()
    Return ok
End Function

#else

'' Finds an installed command-line clipboard tool.
Private Function HaveTool(ByRef tool As Const String) As Boolean
    Return Shell("command -v " & tool & " >/dev/null 2>&1") = 0
End Function

Function Clipboard_SetText(ByRef text As Const String) As Boolean
    Dim As String cmd = ""
    If HaveTool("xclip") Then
        cmd = "xclip -selection clipboard 2>/dev/null"
    ElseIf HaveTool("xsel") Then
        cmd = "xsel --clipboard --input 2>/dev/null"
    ElseIf HaveTool("wl-copy") Then
        cmd = "wl-copy 2>/dev/null"
    Else
        Return False
    End If
    Dim As Integer f = FreeFile
    If Open Pipe(cmd For Output As #f) <> 0 Then Return False
    Print #f, text;
    Close #f
    Return True
End Function

Function Clipboard_GetText(ByRef text As String) As Boolean
    text = ""
    Dim As String cmd = ""
    If HaveTool("xclip") Then
        cmd = "xclip -selection clipboard -o 2>/dev/null"
    ElseIf HaveTool("xsel") Then
        cmd = "xsel --clipboard --output 2>/dev/null"
    ElseIf HaveTool("wl-paste") Then
        cmd = "wl-paste --no-newline 2>/dev/null"
    Else
        Return False
    End If
    Dim As Integer f = FreeFile
    If Open Pipe(cmd For Input As #f) <> 0 Then Return False
    Dim As String ln
    Dim As Boolean first = True
    Do While Not EOF(f)
        Line Input #f, ln
        If Not first Then text &= Chr(10)
        text &= ln
        first = False
    Loop
    Close #f
    Return True
End Function

#endif
