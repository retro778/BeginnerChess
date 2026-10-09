'' =====================================================================
'' BeginnerChess - tests/test_famous.bas
'' Tests for the SQLite wrapper and the Famous Games library.
''   test_famous           with SQLite
''   test_famous --nodb    run with BEGINNERCHESS_SQLITE=/nonexistent to test
''                         the read-only fallback without a database
'' =====================================================================
#include once "../modules/db.bi"
#include once "testutil.bi"
#include once "../modules/famous.bi"
#include once "file.bi"

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

Dim Shared DataRoot As String
DataRoot = ExePath() & "/../data"
Dim Shared TMP As String
TMP = Test_TempDir("cm_test_famous")

Sub TestDbLayer()
    Print "SQLite wrapper..."
    Check DB_Available(), "SQLite library loads", DB_StatusText()
    Kill TMP & "/t.db"
    Check DB_Open(TMP & "/t.db"), "open/create database", DB_LastError()
    Check DB_Exec("CREATE TABLE t(a INTEGER, b TEXT)"), "create table", DB_LastError()
    Dim As DBStatement st = DB_Prepare("INSERT INTO t(a,b) VALUES(?,?)")
    Check st <> 0, "prepare insert"
    Dim As Integer i
    For i = 1 To 5
        DB_BindInt(st, 1, i * 10)
        DB_BindText(st, 2, "row """ & i & """ it's")
        DB_Step(st)
        DB_Reset(st)
    Next
    DB_Finalize(st)
    Check DB_LastInsertId() = 5, "last insert id"
    Check DB_QueryValue("SELECT SUM(a) FROM t") = "150", "query value"
    st = DB_Prepare("SELECT b FROM t WHERE a=?")
    DB_BindInt(st, 1, 30)
    Check DB_Step(st) AndAlso DB_ColText(st, 0) = "row ""3"" it's", "text with quotes round trip"
    DB_Finalize(st)
    Check DB_Exec("SELECT nonsense FROM nowhere") = False AndAlso DB_LastError() <> "", "errors are reported", DB_LastError()
    DB_Close()
End Sub

Sub TestLibrary()
    Print "Famous games library..."
    Kill TMP & "/lib.db"
    Test_CopyFile(DataRoot & "/games/famous.pgn", TMP & "/famous.pgn")
    Dim As Boolean ok = Famous_Init(TMP & "/lib.db", TMP & "/famous.pgn", DataRoot & "/openings/book.txt")
    Check ok AndAlso Famous_UsingDatabase(), "library uses the database", Famous_StatusText()
    Dim As Integer n = Famous_Count()
    Check n = 14, "14 built-in games", Str(n)
    Check Famous_OpeningCount() >= 70, "opening book copied to the database", Str(Famous_OpeningCount())
    Dim As Integer i, mates = 0, sorted = -1
    Static g As ChessGame
    For i = 0 To n - 1
        Dim As FamousGame Ptr fg = Famous_Get(i)
        Dim As PgnTags tags
        Dim As String e
        Check Pgn_ParseGame(fg->pgn, g, tags, e), fg->white & " - " & fg->black & " parses", e
        Check g.moveCount = fg->plies AndAlso fg->plies > 0, fg->white & ": ply count"
        Check fg->intro <> "", fg->white & ": has an introduction"
        If Right(g.sanMoves(g.moveCount - 1), 1) = "#" Then
            Check g.termination = TERM_CHECKMATE, fg->white & ": final # is a real checkmate"
            mates += 1
        End If
        If i > 0 AndAlso fg->year < Famous_Get(i - 1)->year Then sorted = 0
    Next
    Check mates >= 7, "several games end in checkmate", Str(mates)
    Check sorted <> 0, "games are listed by year"
    Check DB_QueryValue("SELECT COUNT(*) FROM game_moves") <> "0", "moves stored in game_moves"

    '' Restart: no duplicates
    Famous_Shutdown()
    Famous_Init(TMP & "/lib.db", TMP & "/famous.pgn", DataRoot & "/openings/book.txt")
    Check Famous_Count() = 14, "no duplicates after restart", Str(Famous_Count())

    '' Adding user games
    Dim As Integer added, skipped
    Dim As String errMsg
    Famous_AddPgnFile(DataRoot & "/games/classics.pgn", added, skipped, errMsg)
    Check added = 0 AndAlso skipped = 3, "games already in the library are skipped", added & "/" & skipped
    Dim As Integer f = FreeFile
    Open TMP & "/mine.pgn" For Output As #f
    Print #f, "[White ""Me""]" & Chr(10) & "[Black ""Friend""]" & Chr(10) & "[Date ""2026.10.07""]" & Chr(10) & _
              "[Result ""1-0""]" & Chr(10) & Chr(10) & "1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0" & Chr(10)
    Print #f, "[White ""Friend""]" & Chr(10) & "[Black ""Me""]" & Chr(10) & "[Result ""*""]" & Chr(10) & Chr(10) & _
              "1. d4 d5 *" & Chr(10)
    Print #f, "[White ""Broken""]" & Chr(10) & "[Black ""Game""]" & Chr(10) & Chr(10) & "1. e4 e5 2. Ke3 *" & Chr(10)
    Close #f
    Check Famous_AddPgnFile(TMP & "/mine.pgn", added, skipped, errMsg) AndAlso added = 2 AndAlso skipped = 1, _
          "user games added, broken game skipped", added & "/" & skipped & " " & errMsg
    Check Famous_Count() = 16, "16 games in the library"
    '' The user games survive a rebuild of the built-in games.
    Open TMP & "/famous.pgn" For Append As #f
    Print #f, Chr(10) & "[White ""Extra""]" & Chr(10) & "[Black ""Game""]" & Chr(10) & "[Date ""2000.01.01""]" & Chr(10) & _
              "[Result ""*""]" & Chr(10) & "[CMIntro ""x""]" & Chr(10) & Chr(10) & "1. c4 *" & Chr(10)
    Close #f
    Famous_Shutdown()
    Famous_Init(TMP & "/lib.db", TMP & "/famous.pgn", DataRoot & "/openings/book.txt")
    Check Famous_Count() = 17, "changed PGN rebuilt, user games kept", Str(Famous_Count())
    '' Delete: only user games
    Dim As Integer userIdx = -1, builtinIdx = -1
    For i = 0 To Famous_Count() - 1
        If Famous_Get(i)->source = "user" AndAlso userIdx < 0 Then userIdx = i
        If Famous_Get(i)->source = "builtin" AndAlso builtinIdx < 0 Then builtinIdx = i
    Next
    Check Famous_Delete(builtinIdx) = False, "built-in games cannot be deleted"
    Check Famous_Delete(userIdx) AndAlso Famous_Count() = 16, "user game deleted"
    Famous_Shutdown()
End Sub

Sub TestFallback()
    Print "Without SQLite..."
    Dim As Boolean ok = Famous_Init(TMP & "/none.db", DataRoot & "/games/famous.pgn", DataRoot & "/openings/book.txt")
    Check ok = False AndAlso Not Famous_UsingDatabase(), "reports that the database is missing", Famous_StatusText()
    Check Famous_Count() = 14, "still shows the built-in games", Str(Famous_Count())
    Dim As Integer added, skipped
    Dim As String errMsg
    Check Famous_AddPgnFile(DataRoot & "/games/classics.pgn", added, skipped, errMsg) = False AndAlso errMsg <> "", _
          "adding games explains why it is not possible", errMsg
End Sub

Print "BeginnerChess famous games tests"
Test_MakeDirs(TMP)
If Command(1) = "--nodb" Then
    TestFallback()
Else
    TestDbLayer()
    TestLibrary()
End If
Print
Print "Passed: " & TestsPassed & "   Failed: " & TestsFailed
If TestsFailed > 0 Then End 1
End 0
