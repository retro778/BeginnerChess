'' =====================================================================
'' BeginnerChess - clipboard.bi
'' Copy and paste text (used for FEN positions and PGN games).
'' Windows: Win32 clipboard API. Linux: the xclip, xsel or wl-copy /
'' wl-paste tools when installed. If none is available the functions
'' return False and the caller offers another way (e.g. a file).
'' =====================================================================
#pragma once

Declare Function Clipboard_SetText(ByRef text As Const String) As Boolean
Declare Function Clipboard_GetText(ByRef text As String) As Boolean
