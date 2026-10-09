'' =====================================================================
'' BeginnerChess - db.bi
'' A small wrapper around SQLite 3. The library is loaded at run time
'' (libsqlite3.so.0 on Linux, sqlite3.dll on Windows), so BeginnerChess
'' still runs without it - callers check DB_Available() and fall back.
'' Declarations follow FreeBASIC's sqlite3.bi (C calling convention on
'' every platform).
'' =====================================================================
#pragma once

Type DBStatement As Any Ptr

Declare Function DB_Load() As Boolean                 '' load the library (once)
Declare Function DB_Available() As Boolean
Declare Function DB_StatusText() As String            '' e.g. "SQLite 3.45.1"
Declare Function DB_Open(ByRef fileName As Const String) As Boolean
Declare Sub DB_Close()
Declare Function DB_IsOpen() As Boolean
Declare Function DB_LastError() As String

'' Runs SQL that returns no rows (CREATE, INSERT without parameters, ...).
Declare Function DB_Exec(ByRef sql As Const String) As Boolean
'' Prepared statements: parameters are numbered from 1, columns from 0.
Declare Function DB_Prepare(ByRef sql As Const String) As DBStatement
Declare Function DB_BindText(ByVal st As DBStatement, ByVal index As Integer, ByRef value As Const String) As Boolean
Declare Function DB_BindInt(ByVal st As DBStatement, ByVal index As Integer, ByVal value As LongInt) As Boolean
'' Returns True while there is a row; False when done or on error.
Declare Function DB_Step(ByVal st As DBStatement) As Boolean
'' True if the last DB_Step finished without an error.
Declare Function DB_StepOk() As Boolean
Declare Function DB_ColText(ByVal st As DBStatement, ByVal col As Integer) As String
Declare Function DB_ColInt(ByVal st As DBStatement, ByVal col As Integer) As LongInt
Declare Sub DB_Reset(ByVal st As DBStatement)
Declare Sub DB_Finalize(ByVal st As DBStatement)
Declare Function DB_LastInsertId() As LongInt
Declare Function DB_Begin() As Boolean
Declare Function DB_Commit() As Boolean
'' Value of the first column of the first row, or def.
Declare Function DB_QueryValue(ByRef sql As Const String, ByRef def As Const String = "") As String
