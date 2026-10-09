'' =====================================================================
'' BeginnerChess - db.bas
'' See db.bi.
'' =====================================================================
#include once "db.bi"

Const SQLITE_OK = 0
Const SQLITE_ROW = 100
Const SQLITE_DONE = 101
Const SQLITE_OPEN_READWRITE = &h00000002
Const SQLITE_OPEN_CREATE = &h00000004

Type FnOpenV2 As Function Cdecl (ByVal filename As Const ZString Ptr, ByVal ppDb As Any Ptr Ptr, _
                                 ByVal flags As Long, ByVal zVfs As Const ZString Ptr) As Long
Type FnClose As Function Cdecl (ByVal db As Any Ptr) As Long
Type FnExec As Function Cdecl (ByVal db As Any Ptr, ByVal sql As Const ZString Ptr, ByVal callback As Any Ptr, _
                               ByVal arg As Any Ptr, ByVal errmsg As Any Ptr) As Long
Type FnPrepareV2 As Function Cdecl (ByVal db As Any Ptr, ByVal zSql As Const ZString Ptr, ByVal nByte As Long, _
                                    ByVal ppStmt As Any Ptr Ptr, ByVal pzTail As Any Ptr) As Long
Type FnBindText As Function Cdecl (ByVal st As Any Ptr, ByVal idx As Long, ByVal txt As Const ZString Ptr, _
                                   ByVal n As Long, ByVal destructor As Any Ptr) As Long
Type FnBindInt64 As Function Cdecl (ByVal st As Any Ptr, ByVal idx As Long, ByVal value As LongInt) As Long
Type FnStep As Function Cdecl (ByVal st As Any Ptr) As Long
Type FnColText As Function Cdecl (ByVal st As Any Ptr, ByVal iCol As Long) As Const UByte Ptr
Type FnColInt64 As Function Cdecl (ByVal st As Any Ptr, ByVal iCol As Long) As LongInt
Type FnFinalize As Function Cdecl (ByVal st As Any Ptr) As Long
Type FnErrMsg As Function Cdecl (ByVal db As Any Ptr) As Const ZString Ptr
Type FnLibVersion As Function Cdecl () As Const ZString Ptr
Type FnLastInsert As Function Cdecl (ByVal db As Any Ptr) As LongInt

Dim Shared SqlLib As Any Ptr = 0
Dim Shared SqlTried As Boolean = False
Dim Shared pOpenV2 As FnOpenV2
Dim Shared pClose As FnClose
Dim Shared pExec As FnExec
Dim Shared pPrepare As FnPrepareV2
Dim Shared pBindText As FnBindText
Dim Shared pBindInt64 As FnBindInt64
Dim Shared pStep As FnStep
Dim Shared pColText As FnColText
Dim Shared pColInt64 As FnColInt64
Dim Shared pFinalize As FnFinalize
Dim Shared pResetStmt As FnFinalize
Dim Shared pErrMsg As FnErrMsg
Dim Shared pLibVersion As FnLibVersion
Dim Shared pLastInsert As FnLastInsert

Dim Shared Handle As Any Ptr = 0
Dim Shared LastError As String
Dim Shared LastStepOk As Boolean = True
Dim Shared StatusText As String

Function DB_Load() As Boolean
    If SqlLib Then Return True
    If SqlTried Then Return False
    SqlTried = True
    Dim As String candidates(0 To 3)
#ifdef __FB_WIN32__
    candidates(0) = ExePath() & "\sqlite3.dll" : candidates(1) = "sqlite3.dll"
    candidates(2) = "sqlite3" : candidates(3) = ""
#else
    candidates(0) = ExePath() & "/libsqlite3.so.0" : candidates(1) = "libsqlite3.so.0"
    candidates(2) = "libsqlite3.so" : candidates(3) = "sqlite3"
#endif
    '' BEGINNERCHESS_SQLITE=<file> forces a specific library (for testing).
    If Environ("BEGINNERCHESS_SQLITE") <> "" Then
        candidates(0) = Environ("BEGINNERCHESS_SQLITE")
        candidates(1) = "" : candidates(2) = "" : candidates(3) = ""
    End If
    Dim As Integer i
    For i = 0 To 3
        If candidates(i) = "" Then Continue For
        SqlLib = DyLibLoad(candidates(i))
        If SqlLib Then Exit For
    Next
    If SqlLib = 0 Then
        StatusText = "SQLite library not found"
        LastError = StatusText
        Return False
    End If
    pOpenV2 = DyLibSymbol(SqlLib, "sqlite3_open_v2")
    pClose = DyLibSymbol(SqlLib, "sqlite3_close")
    pExec = DyLibSymbol(SqlLib, "sqlite3_exec")
    pPrepare = DyLibSymbol(SqlLib, "sqlite3_prepare_v2")
    pBindText = DyLibSymbol(SqlLib, "sqlite3_bind_text")
    pBindInt64 = DyLibSymbol(SqlLib, "sqlite3_bind_int64")
    pStep = DyLibSymbol(SqlLib, "sqlite3_step")
    pColText = DyLibSymbol(SqlLib, "sqlite3_column_text")
    pColInt64 = DyLibSymbol(SqlLib, "sqlite3_column_int64")
    pFinalize = DyLibSymbol(SqlLib, "sqlite3_finalize")
    pResetStmt = DyLibSymbol(SqlLib, "sqlite3_reset")
    pErrMsg = DyLibSymbol(SqlLib, "sqlite3_errmsg")
    pLibVersion = DyLibSymbol(SqlLib, "sqlite3_libversion")
    pLastInsert = DyLibSymbol(SqlLib, "sqlite3_last_insert_rowid")
    If pOpenV2 = 0 OrElse pClose = 0 OrElse pExec = 0 OrElse pPrepare = 0 OrElse pBindText = 0 _
       OrElse pBindInt64 = 0 OrElse pStep = 0 OrElse pColText = 0 OrElse pColInt64 = 0 OrElse pFinalize = 0 _
       OrElse pResetStmt = 0 OrElse pErrMsg = 0 OrElse pLibVersion = 0 OrElse pLastInsert = 0 Then
        DyLibFree SqlLib
        SqlLib = 0
        StatusText = "SQLite library is incomplete"
        LastError = StatusText
        Return False
    End If
    StatusText = "SQLite " & *pLibVersion()
    Return True
End Function

Function DB_Available() As Boolean
    Return DB_Load()
End Function

Function DB_StatusText() As String
    DB_Load()
    Return StatusText
End Function

Function DB_LastError() As String
    Return LastError
End Function

Private Sub SetError()
    If Handle Then LastError = *pErrMsg(Handle) Else LastError = "database not open"
End Sub

Function DB_Open(ByRef fileName As Const String) As Boolean
    If Not DB_Load() Then Return False
    DB_Close()
    Dim As Long rc = pOpenV2(StrPtr(fileName), @Handle, SQLITE_OPEN_READWRITE Or SQLITE_OPEN_CREATE, 0)
    If rc <> SQLITE_OK Then
        SetError()
        If Handle Then pClose(Handle)
        Handle = 0
        Return False
    End If
    Return True
End Function

Sub DB_Close()
    If Handle Then pClose(Handle)
    Handle = 0
End Sub

Function DB_IsOpen() As Boolean
    Return Handle <> 0
End Function

Function DB_Exec(ByRef sql As Const String) As Boolean
    If Handle = 0 Then LastError = "database not open" : Return False
    If pExec(Handle, StrPtr(sql), 0, 0, 0) <> SQLITE_OK Then
        SetError()
        Return False
    End If
    Return True
End Function

Function DB_Prepare(ByRef sql As Const String) As DBStatement
    If Handle = 0 Then LastError = "database not open" : Return 0
    Dim As Any Ptr st = 0
    If pPrepare(Handle, StrPtr(sql), -1, @st, 0) <> SQLITE_OK Then
        SetError()
        Return 0
    End If
    Return st
End Function

Function DB_BindText(ByVal st As DBStatement, ByVal index As Integer, ByRef value As Const String) As Boolean
    If st = 0 Then Return False
    '' -1 = SQLITE_TRANSIENT: SQLite copies the text immediately.
    Return pBindText(st, index, StrPtr(value), Len(value), Cast(Any Ptr, -1)) = SQLITE_OK
End Function

Function DB_BindInt(ByVal st As DBStatement, ByVal index As Integer, ByVal value As LongInt) As Boolean
    If st = 0 Then Return False
    Return pBindInt64(st, index, value) = SQLITE_OK
End Function

Function DB_Step(ByVal st As DBStatement) As Boolean
    If st = 0 Then LastStepOk = False : Return False
    Dim As Long rc = pStep(st)
    If rc = SQLITE_ROW Then LastStepOk = True : Return True
    LastStepOk = (rc = SQLITE_DONE)
    If Not LastStepOk Then SetError()
    Return False
End Function

Function DB_StepOk() As Boolean
    Return LastStepOk
End Function

Function DB_ColText(ByVal st As DBStatement, ByVal col As Integer) As String
    If st = 0 Then Return ""
    Dim As Const UByte Ptr p = pColText(st, col)
    If p = 0 Then Return ""
    Return *Cast(ZString Ptr, p)
End Function

Function DB_ColInt(ByVal st As DBStatement, ByVal col As Integer) As LongInt
    If st = 0 Then Return 0
    Return pColInt64(st, col)
End Function

Sub DB_Reset(ByVal st As DBStatement)
    If st Then pResetStmt(st)
End Sub

Sub DB_Finalize(ByVal st As DBStatement)
    If st Then pFinalize(st)
End Sub

Function DB_LastInsertId() As LongInt
    If Handle = 0 Then Return 0
    Return pLastInsert(Handle)
End Function

Function DB_Begin() As Boolean
    Return DB_Exec("BEGIN TRANSACTION")
End Function

Function DB_Commit() As Boolean
    Return DB_Exec("COMMIT")
End Function

Function DB_QueryValue(ByRef sql As Const String, ByRef def As Const String = "") As String
    Dim As DBStatement st = DB_Prepare(sql)
    If st = 0 Then Return def
    Dim As String v = def
    If DB_Step(st) Then v = DB_ColText(st, 0)
    DB_Finalize(st)
    Return v
End Function
