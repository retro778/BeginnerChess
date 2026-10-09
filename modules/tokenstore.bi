'' =====================================================================
'' BeginnerChess - tokenstore.bi
'' Keeps the online session token of "remember me" - never the password.
''
''   Windows: encrypted with DPAPI (CryptProtectData, bound to the Windows
''            user account) in %APPDATA%\BeginnerChess\online-<server>.token
''   Linux:   ~/.beginnerchess/online-<server>.token, readable only by the
''            user (folder 0700, file 0600)
''
'' The token is never written to the settings file. It belongs to one server
'' (accounts are per server). Deleting the file (or logging out) forgets it.
'' =====================================================================
#pragma once

Declare Function Token_Save(ByRef serverHost As Const String, ByRef token As Const String) As Boolean
Declare Function Token_Load(ByRef serverHost As Const String) As String      '' "" if none
Declare Sub Token_Delete(ByRef serverHost As Const String)
'' Where tokens are kept (for documentation and tests).
Declare Function Token_Folder() As String
'' For tests: use another folder.
Declare Sub Token_SetFolder(ByRef folder As Const String)
