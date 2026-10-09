'' =====================================================================
'' BeginnerChess - famous.bas
'' See famous.bi.
'' =====================================================================
#include once "famous.bi"
#include once "db.bi"
#include once "file.bi"

Dim Shared Games() As FamousGame
Dim Shared GameCount As Integer = 0
Dim Shared UsingDb As Boolean = False
Dim Shared Status As String

Const SCHEMA_VERSION = "1"

Function Famous_UsingDatabase() As Boolean
    Return UsingDb
End Function

Function Famous_StatusText() As String
    Return Status
End Function

Function Famous_Count() As Integer
    Return GameCount
End Function

Function Famous_Get(ByVal index As Integer) As FamousGame Ptr
    If index < 0 OrElse index >= GameCount Then Return 0
    Return @Games(index)
End Function

'' Simple signature of a text file (size + checksum) to notice changes.
Private Function FileSignature(ByRef fileName As Const String) As String
    Dim As String text
    If Not Pgn_ReadFile(fileName, text) Then Return ""
    Dim As ULong h = 2166136261UL
    Dim As Integer i
    For i = 0 To Len(text) - 1
        h = (h Xor text[i]) * 16777619UL
    Next
    Return Len(text) & ":" & Hex(h, 8)
End Function

Private Function YearOf(ByRef d As Const String) As Integer
    Dim As String y = Left(d, 4)
    If Len(y) = 4 AndAlso Val(y) > 0 Then Return ValInt(y)
    Return 0
End Function

'' Fills a FamousGame from one PGN game text. Returns False if it does not parse.
Private Function GameFromPgn(ByRef text As Const String, ByRef fg As FamousGame, ByRef g As ChessGame, _
                             ByRef errMsg As String) As Boolean
    Dim As PgnTags tags
    If Not Pgn_ParseGame(text, g, tags, errMsg) Then Return False
    fg.white = Pgn_GetTag(tags, "White", "?")
    fg.black = Pgn_GetTag(tags, "Black", "?")
    fg.event = Pgn_GetTag(tags, "Event", "")
    fg.site = Pgn_GetTag(tags, "Site", "")
    fg.dateStr = Pgn_GetTag(tags, "Date", "")
    fg.year = YearOf(fg.dateStr)
    fg.result = Pgn_GetTag(tags, "Result", "*")
    fg.eco = Pgn_GetTag(tags, "ECO", "")
    fg.opening = Pgn_GetTag(tags, "Opening", "")
    fg.intro = Pgn_GetTag(tags, "CMIntro", "")
    fg.plies = g.moveCount
    fg.pgn = text
    Return True
End Function

Private Sub AddToMemory(ByRef fg As FamousGame)
    If GameCount > UBound(Games) Then ReDim Preserve Games(0 To GameCount * 2 + 15)
    Games(GameCount) = fg
    GameCount += 1
End Sub

'' Inserts a game (and its moves) into the database.
Private Function InsertGame(ByRef fg As FamousGame, ByRef g As ChessGame) As Boolean
    Dim As DBStatement st = DB_Prepare("INSERT INTO famous_games(white,black,event,site,date,year,result,eco," & _
                                       "opening,intro,source,plies,pgn) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)")
    If st = 0 Then Return False
    DB_BindText(st, 1, fg.white) : DB_BindText(st, 2, fg.black) : DB_BindText(st, 3, fg.event)
    DB_BindText(st, 4, fg.site) : DB_BindText(st, 5, fg.dateStr) : DB_BindInt(st, 6, fg.year)
    DB_BindText(st, 7, fg.result) : DB_BindText(st, 8, fg.eco) : DB_BindText(st, 9, fg.opening)
    DB_BindText(st, 10, fg.intro) : DB_BindText(st, 11, fg.source) : DB_BindInt(st, 12, fg.plies)
    DB_BindText(st, 13, fg.pgn)
    DB_Step(st)
    Dim As Boolean ok = DB_StepOk()
    DB_Finalize(st)
    If Not ok Then Return False
    Dim As LongInt gid = DB_LastInsertId()
    st = DB_Prepare("INSERT INTO game_moves(game_id,ply,san,comment) VALUES(?,?,?,?)")
    If st = 0 Then Return False
    Dim As Integer i
    For i = 0 To g.moveCount - 1
        DB_BindInt(st, 1, gid) : DB_BindInt(st, 2, i + 1)
        DB_BindText(st, 3, g.sanMoves(i)) : DB_BindText(st, 4, g.comments(i))
        DB_Step(st)
        DB_Reset(st)
    Next
    DB_Finalize(st)
    Return True
End Function

Private Function CreateSchema() As Boolean
    Return DB_Exec("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)") _
        AndAlso DB_Exec("CREATE TABLE IF NOT EXISTS famous_games(id INTEGER PRIMARY KEY AUTOINCREMENT, " & _
                        "white TEXT, black TEXT, event TEXT, site TEXT, date TEXT, year INTEGER, result TEXT, " & _
                        "eco TEXT, opening TEXT, intro TEXT, source TEXT, plies INTEGER, pgn TEXT)") _
        AndAlso DB_Exec("CREATE TABLE IF NOT EXISTS game_moves(game_id INTEGER, ply INTEGER, san TEXT, " & _
                        "comment TEXT, PRIMARY KEY(game_id, ply))") _
        AndAlso DB_Exec("CREATE TABLE IF NOT EXISTS openings(eco TEXT, name TEXT, moves TEXT)") _
        AndAlso DB_Exec("CREATE INDEX IF NOT EXISTS idx_famous_year ON famous_games(year)")
End Function

Private Sub SetMeta(ByRef key As Const String, ByRef value As Const String)
    Dim As DBStatement st = DB_Prepare("INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)")
    DB_BindText(st, 1, key)
    DB_BindText(st, 2, value)
    DB_Step(st)
    DB_Finalize(st)
End Sub

Private Function GetMeta(ByRef key As Const String) As String
    Dim As DBStatement st = DB_Prepare("SELECT value FROM meta WHERE key=?")
    If st = 0 Then Return ""
    DB_BindText(st, 1, key)
    Dim As String v = ""
    If DB_Step(st) Then v = DB_ColText(st, 0)
    DB_Finalize(st)
    Return v
End Function

'' Rebuilds the built-in games from the PGN file.
Private Function RebuildBuiltin(ByRef famousPgn As Const String) As Boolean
    Dim As String text, errMsg
    If Not Pgn_ReadFile(famousPgn, text) Then Return False
    Dim As String parts()
    ReDim parts(0 To 31)
    Dim As Integer n = Pgn_SplitGames(text, parts()), i
    DB_Begin()
    DB_Exec("DELETE FROM game_moves WHERE game_id IN (SELECT id FROM famous_games WHERE source='builtin')")
    DB_Exec("DELETE FROM famous_games WHERE source='builtin'")
    Static g As ChessGame
    For i = 0 To n - 1
        Dim As FamousGame fg
        If GameFromPgn(parts(i), fg, g, errMsg) Then
            fg.source = "builtin"
            InsertGame(fg, g)
        End If
    Next
    Return DB_Commit()
End Function

'' Copies the opening book into the openings table.
Private Sub RebuildOpenings(ByRef bookFile As Const String)
    Dim As Integer f = FreeFile
    If Open(bookFile For Input As #f) <> 0 Then Exit Sub
    DB_Begin()
    DB_Exec("DELETE FROM openings")
    Dim As DBStatement st = DB_Prepare("INSERT INTO openings(eco,name,moves) VALUES(?,?,?)")
    Dim As String ln
    Do While Not EOF(f)
        Line Input #f, ln
        ln = Trim(ln, Any " " & Chr(9, 13))
        If ln = "" OrElse Left(ln, 1) = "#" Then Continue Do
        Dim As Integer b1 = InStr(ln, "|"), b2 = InStr(b1 + 1, ln, "|")
        If b1 = 0 OrElse b2 = 0 Then Continue Do
        DB_BindText(st, 1, Trim(Left(ln, b1 - 1)))
        DB_BindText(st, 2, Trim(Mid(ln, b1 + 1, b2 - b1 - 1)))
        DB_BindText(st, 3, Trim(Mid(ln, b2 + 1)))
        DB_Step(st)
        DB_Reset(st)
    Loop
    DB_Finalize(st)
    DB_Commit()
    Close #f
End Sub

Private Sub LoadFromDatabase()
    Erase Games
    ReDim Games(0 To 31)
    GameCount = 0
    Dim As DBStatement st = DB_Prepare("SELECT id,white,black,event,site,date,year,result,eco,opening,intro," & _
                                       "source,plies,pgn FROM famous_games ORDER BY year, id")
    Do While DB_Step(st)
        Dim As FamousGame fg
        fg.id = DB_ColInt(st, 0) : fg.white = DB_ColText(st, 1) : fg.black = DB_ColText(st, 2)
        fg.event = DB_ColText(st, 3) : fg.site = DB_ColText(st, 4) : fg.dateStr = DB_ColText(st, 5)
        fg.year = DB_ColInt(st, 6) : fg.result = DB_ColText(st, 7) : fg.eco = DB_ColText(st, 8)
        fg.opening = DB_ColText(st, 9) : fg.intro = DB_ColText(st, 10) : fg.source = DB_ColText(st, 11)
        fg.plies = DB_ColInt(st, 12) : fg.pgn = DB_ColText(st, 13)
        AddToMemory(fg)
    Loop
    DB_Finalize(st)
End Sub

'' Without a database: read the built-in PGN file directly.
Private Sub LoadFromPgn(ByRef famousPgn As Const String)
    Erase Games
    ReDim Games(0 To 31)
    GameCount = 0
    Dim As String text, errMsg
    If Not Pgn_ReadFile(famousPgn, text) Then Exit Sub
    Dim As String parts()
    ReDim parts(0 To 31)
    Dim As Integer n = Pgn_SplitGames(text, parts()), i
    Static g As ChessGame
    For i = 0 To n - 1
        Dim As FamousGame fg
        If GameFromPgn(parts(i), fg, g, errMsg) Then
            fg.source = "builtin"
            fg.id = i + 1
            AddToMemory(fg)
        End If
    Next
End Sub

Function Famous_Init(ByRef dbFile As Const String, ByRef famousPgn As Const String, _
                     ByRef bookFile As Const String) As Boolean
    UsingDb = False
    If DB_Open(dbFile) AndAlso CreateSchema() Then
        UsingDb = True
        Dim As String sig = FileSignature(famousPgn)
        If sig <> "" AndAlso (GetMeta("famous_signature") <> sig OrElse GetMeta("schema") <> SCHEMA_VERSION) Then
            If RebuildBuiltin(famousPgn) Then
                SetMeta("famous_signature", sig)
                SetMeta("schema", SCHEMA_VERSION)
            End If
        End If
        Dim As String bsig = FileSignature(bookFile)
        If bsig <> "" AndAlso GetMeta("book_signature") <> bsig Then
            RebuildOpenings(bookFile)
            SetMeta("book_signature", bsig)
        End If
        LoadFromDatabase()
        Status = "Game library: " & DB_StatusText() & " database (" & GameCount & " games)"
        Return True
    End If
    '' Fallback
    Dim As String why = DB_LastError()
    DB_Close()
    LoadFromPgn(famousPgn)
    Status = "The game database is not available (" & why & "). Showing the built-in games only; " & _
             "adding games to the library needs SQLite."
    Return False
End Function

Sub Famous_Shutdown()
    DB_Close()
End Sub

Function Famous_AddPgnFile(ByRef fileName As Const String, ByRef added As Integer, _
                           ByRef skipped As Integer, ByRef errMsg As String) As Boolean
    added = 0 : skipped = 0 : errMsg = ""
    If Not UsingDb Then
        errMsg = "Adding games needs the SQLite database, which is not available."
        Return False
    End If
    Dim As String text
    If Not Pgn_ReadFile(fileName, text) Then
        errMsg = "The file could not be read: " & fileName
        Return False
    End If
    Dim As String parts()
    ReDim parts(0 To 31)
    Dim As Integer n = Pgn_SplitGames(text, parts()), i
    If n = 0 Then
        errMsg = "No games were found in the file."
        Return False
    End If
    Static g As ChessGame
    DB_Begin()
    For i = 0 To n - 1
        Dim As FamousGame fg
        Dim As String why
        If Not GameFromPgn(parts(i), fg, g, why) Then
            skipped += 1
            If errMsg = "" Then errMsg = "Game " & (i + 1) & ": " & why
            Continue For
        End If
        '' Skip games that are already in the library.
        Dim As DBStatement st = DB_Prepare("SELECT COUNT(*) FROM famous_games WHERE white=? AND black=? AND date=? AND plies=?")
        DB_BindText(st, 1, fg.white) : DB_BindText(st, 2, fg.black)
        DB_BindText(st, 3, fg.dateStr) : DB_BindInt(st, 4, fg.plies)
        Dim As Boolean dup = False
        If DB_Step(st) Then dup = (DB_ColInt(st, 0) > 0)
        DB_Finalize(st)
        If dup Then
            skipped += 1
            Continue For
        End If
        fg.source = "user"
        If InsertGame(fg, g) Then added += 1 Else skipped += 1
    Next
    DB_Commit()
    LoadFromDatabase()
    Return added > 0
End Function

Function Famous_Delete(ByVal index As Integer) As Boolean
    If Not UsingDb OrElse index < 0 OrElse index >= GameCount Then Return False
    If Games(index).source <> "user" Then Return False
    Dim As DBStatement st = DB_Prepare("DELETE FROM game_moves WHERE game_id=?")
    DB_BindInt(st, 1, Games(index).id) : DB_Step(st) : DB_Finalize(st)
    st = DB_Prepare("DELETE FROM famous_games WHERE id=?")
    DB_BindInt(st, 1, Games(index).id) : DB_Step(st)
    Dim As Boolean ok = DB_StepOk()
    DB_Finalize(st)
    LoadFromDatabase()
    Return ok
End Function

Function Famous_OpeningCount() As Integer
    If Not UsingDb Then Return 0
    Return ValInt(DB_QueryValue("SELECT COUNT(*) FROM openings", "0"))
End Function
