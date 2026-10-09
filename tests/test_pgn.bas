'' =====================================================================
'' BeginnerChess - tests/test_pgn.bas
'' Tests for PGN import/export and save games.
'' =====================================================================
#include once "../modules/pgn.bi"
#include once "testutil.bi"
#include once "../modules/savegame.bi"
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

Const NL = !"\n"

'' Morphy's "Opera Game", Paris 1858 (the moves are public domain).
Dim Shared OperaGame As String
OperaGame = "[Event ""Paris""]" & NL & "[Site ""Paris FRA""]" & NL & "[Date ""1858.??.??""]" & NL & _
    "[Round ""?""]" & NL & "[White ""Paul Morphy""]" & NL & _
    "[Black ""Duke Karl / Count Isouard""]" & NL & "[Result ""1-0""]" & NL & NL & _
    "1. e4 e5 2. Nf3 d6 {The Philidor Defence.} 3. d4 Bg4 $2 4. dxe5 Bxf3 (4... dxe5 5. Qxd8+ Kxd8 6. Nxe5) " & NL & _
    "5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 Qe7 8. Nc3 c6 9. Bg5 b5 10. Nxb5! cxb5 11. Bxb5+ Nbd7 " & NL & _
    "12. O-O-O Rd8 13. Rxd7 Rxd7 14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+!! Nxb8 17. Rd8# 1-0" & NL

Sub TestParse()
    Print "PGN reading..."
    Static g As ChessGame
    Dim As PgnTags tags
    Dim As String errMsg
    Check Pgn_ParseGame(OperaGame, g, tags, errMsg), "Opera Game parses", errMsg
    Check g.moveCount = 33, "33 plies", Str(g.moveCount)
    Check g.termination = TERM_CHECKMATE AndAlso g.result = RESULT_WHITE_WINS, "ends in checkmate"
    Check Pgn_GetTag(tags, "White") = "Paul Morphy", "White tag"
    Check Pgn_GetTag(tags, "Black") = "Duke Karl / Count Isouard", "Black tag"
    Check g.comments(3) = "The Philidor Defence.", "comment attached to 2...d6", g.comments(3)
    Check g.sanMoves(32) = "Rd8#", "last move", g.sanMoves(32)

    '' Escapes, castling with zeros, line comments, results without mate
    Dim As String t = "[Event ""A \""quoted\"" event""]" & NL & "[Result ""0-1""]" & NL & NL & _
        "1. e4 e5 ; a line comment 2. Nf4" & NL & "2. Nf3 Nc6 3. Bc4 Nf6 4. 0-0 Bc5 0-1"
    Check Pgn_ParseGame(t, g, tags, errMsg), "escaped tag and 0-0 parse", errMsg
    Check Pgn_GetTag(tags, "Event") = "A ""quoted"" event", "escaped quotes", Pgn_GetTag(tags, "Event")
    Check g.moveCount = 8 AndAlso g.sanMoves(6) = "O-O", "castling with zeros"
    Check g.termination = TERM_RESIGNATION AndAlso g.result = RESULT_BLACK_WINS, "0-1 without mate = resignation"

    t = "[Result ""1/2-1/2""]" & NL & NL & "1. d4 d5 1/2-1/2"
    Check Pgn_ParseGame(t, g, tags, errMsg) AndAlso g.termination = TERM_AGREEMENT, "draw result = agreement"

    '' From a position
    t = "[SetUp ""1""]" & NL & "[FEN ""4k3/8/8/8/8/8/4P3/4K3 b - - 0 40""]" & NL & NL & "40... Kd7 41. e4 Ke6 *"
    Check Pgn_ParseGame(t, g, tags, errMsg) AndAlso g.moveCount = 3, "game from FEN", errMsg
    Check Game_IsOver(g) = False, "unfinished game stays open"

    '' Errors
    t = "1. e4 e5 2. Nf3 Nc6 3. Bb6 a6 *"
    Check Pgn_ParseGame(t, g, tags, errMsg) = False AndAlso InStr(errMsg, "Bb6") > 0, "illegal move reported", errMsg
    t = "[FEN ""nonsense""]" & NL & NL & "1. e4 *"
    Check Pgn_ParseGame(t, g, tags, errMsg) = False, "bad FEN tag reported", errMsg

    '' Several games in one file
    Dim As String games()
    ReDim games(0 To 1)
    Dim As String two = OperaGame & NL & "[Event ""Second""]" & NL & NL & "1. c4 e5 *" & NL
    Check Pgn_SplitGames(two, games()) = 2, "two games found"
    Pgn_ParseTags(games(1), tags)
    Check Pgn_GetTag(tags, "Event") = "Second", "second game's tags"
    Dim As String multi = "1. e4 {A comment" & NL & "over two   lines} e5 *"
    Check Pgn_ParseGame(multi, g, tags, errMsg) AndAlso g.comments(0) = "A comment over two lines", _
          "comment line breaks and spaces normalised", g.comments(0)
End Sub

Sub TestExport()
    Print "PGN writing..."
    Static g As ChessGame, g2 As ChessGame
    Dim As PgnTags tags, tags2
    Dim As String errMsg
    Pgn_ParseGame(OperaGame, g, tags, errMsg)
    Dim As String pgn = Pgn_Export(g, tags)
    Check InStr(pgn, "[White ""Paul Morphy""]") > 0, "tags written"
    Check InStr(pgn, "[PlyCount ""33""]") > 0, "PlyCount written"
    Check InStr(pgn, "17. Rd8# 1-0") > 0, "movetext and result written"
    Check InStr(pgn, "{The Philidor Defence.} 3. d4") > 0, "comment written"
    Dim As Integer i, longest = 0, startPos = 1
    For i = 1 To Len(pgn)
        If Mid(pgn, i, 1) = NL Then
            If i - startPos > longest Then longest = i - startPos
            startPos = i + 1
        End If
    Next
    Check longest < 80, "lines shorter than 80 characters", Str(longest)
    Check Pgn_ParseGame(pgn, g2, tags2, errMsg) AndAlso Pos_GetFEN(g2.pos) = Pos_GetFEN(g.pos) _
          AndAlso g2.moveCount = g.moveCount, "export/import round trip", errMsg

    '' Special moves and a FEN start
    Dim As String fen = "r3k2r/1P6/8/3pP3/8/8/8/R3K2R w KQkq d6 0 20"
    Game_NewFromFEN(g, fen, errMsg)
    For i = 0 To 0 : Next
    Dim As String mv(0 To 5) = {"exd6", "O-O", "bxa8=Q", "Kg7", "O-O-O", "Rxa8"}
    For i = 0 To 5
        Game_PlayMoveText(g, mv(i), errMsg)
    Next
    Check g.moveCount = 6, "special moves played", errMsg
    Pgn_ClearTags(tags)
    pgn = Pgn_Export(g, tags)
    Check InStr(pgn, "[FEN """ & fen & """]") > 0 AndAlso InStr(pgn, "[SetUp ""1""]") > 0, "FEN tag written"
    Check InStr(pgn, "[Event ""?""]") > 0, "missing roster tags become ?"
    Check Pgn_ParseGame(pgn, g2, tags2, errMsg) AndAlso Pos_GetFEN(g2.pos) = Pos_GetFEN(g.pos), _
          "round trip with en passant, castling, promotion", errMsg
End Sub

Sub TestSaves()
    Print "Save games..."
    Dim As String dirName = Test_TempDir("cm_test_saves")
    Test_RemoveTree(dirName)
    Save_SetDirectory(dirName)
    Check Save_EnsureDirectory(), "save folder created"

    Static g As ChessGame, g2 As ChessGame
    Dim As String errMsg
    Game_New(g)
    Dim As String moves(0 To 9) = {"e4", "e5", "Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1", "Ng8"}
    Dim As Integer i
    For i = 0 To 9 : Game_PlayMoveText(g, moves(i), errMsg) : Next
    Dim As SaveSetup su, su2
    su.opponent = 1 : su.playAs = 1 : su.difficulty = 3 : su.style = 2 : su.humanSide = SIDE_BLACK : su.flipped = True
    su.practice = True
    Check Save_Write(3, g, su, errMsg), "save to slot 3", errMsg
    Check FileExists(Save_SlotFile(3)), "slot file exists"
    Check Save_Read(3, g2, su2, errMsg), "load slot 3", errMsg
    Check Pos_GetFEN(g2.pos) = Pos_GetFEN(g.pos) AndAlso g2.moveCount = 10, "position restored"
    Dim As Boolean settingsOk = (su2.opponent = 1) AndAlso (su2.difficulty = 3) AndAlso (su2.style = 2)
    If su2.humanSide <> SIDE_BLACK OrElse su2.playAs <> 1 Then settingsOk = False
    If Not su2.flipped Then settingsOk = False
    Check settingsOk, "settings restored"
    Check Game_ClaimableDraw(g2) = TERM_THREEFOLD, "history restored (threefold claim still possible)"
    Check su2.practice, "practice flag restored"

    Dim As SaveInfo info
    Check Save_ReadInfo(3, info) AndAlso info.valid AndAlso info.moveCount = 10, "slot info", info.description
    Check InStr(info.description, "Computer") > 0, "slot description", info.description
    Check Left(info.description, 9) = "Practice:", "practice game described as practice", info.description
    Check Save_ReadInfo(5, info) = False AndAlso Not info.exists, "empty slot"
    Check Save_Read(5, g2, su2, errMsg) = False, "loading an empty slot fails", errMsg

    '' A finished game keeps how it ended.
    Game_ClaimDraw(g)
    Save_Write(4, g, su, errMsg)
    Check Save_Read(4, g2, su2, errMsg) AndAlso g2.termination = TERM_THREEFOLD, "claimed draw restored", Str(g2.termination)

    '' Damaged files are detected, not crashed on.
    Dim As String text
    Pgn_ReadFile(Save_SlotFile(3), text)
    Dim As Integer p = InStr(text, "[CMFEN """)
    Mid(text, p + 8, 1) = "x"
    Pgn_WriteFile(Save_SlotFile(6), text)
    Check Save_Read(6, g2, su2, errMsg) = False AndAlso InStr(errMsg, "damaged") > 0, "tampered position detected", errMsg
    Pgn_WriteFile(Save_SlotFile(7), "[Event ""x""]" & NL & NL & "1. e4 e5 2. Ke3 *")
    Check Save_Read(7, g2, su2, errMsg) = False, "illegal move in save detected", errMsg
    Pgn_WriteFile(Save_SlotFile(8), Chr(0, 1, 2, 255) & "garbage")
    Check Save_Read(8, g2, su2, errMsg) = False OrElse g2.moveCount = 0, "garbage file handled", errMsg

    '' A save written by the former "ChessMaster" version still loads.
    Pgn_WriteFile(Save_SlotFile(5), _
        "[Event ""Game against ChessMaster""]" & NL & "[Site ""ChessMaster""]" & NL & _
        "[White ""Player""]" & NL & "[Black ""ChessMaster (Normal, Balanced)""]" & NL & "[Result ""*""]" & NL & _
        "[CMVersion ""1.0.0""]" & NL & "[CMOpponent ""1""]" & NL & "[CMLevel ""2""]" & NL & _
        "[CMHumanSide ""w""]" & NL & NL & "1. e4 e5 2. Nf3 *" & NL)
    Check Save_Read(5, g2, su2, errMsg) AndAlso g2.moveCount = 3 AndAlso su2.opponent = 1, "old ChessMaster save loads", errMsg
    Save_Delete(5)

    Check Save_Delete(3) AndAlso (FileExists(Save_SlotFile(3)) = 0), "delete slot"
    Test_RemoveTree(dirName)
End Sub

Sub TestClassics()
    Print "Bundled games..."
    Dim As String text, errMsg
    Check Pgn_ReadFile(ExePath() & "/../data/games/classics.pgn", text), "classics.pgn readable"
    Dim As String games()
    ReDim games(0 To 3)
    Dim As Integer n = Pgn_SplitGames(text, games()), i
    Check n = 3, "three classic games", Str(n)
    Static g As ChessGame
    Dim As PgnTags tags
    For i = 0 To n - 1
        Dim As Boolean ok = Pgn_ParseGame(games(i), g, tags, errMsg)
        Check ok AndAlso g.termination = TERM_CHECKMATE, "classic game " & (i + 1) & " ends in mate", errMsg
    Next
End Sub

Print "BeginnerChess PGN and save-game tests"
TestParse()
TestExport()
TestSaves()
TestClassics()
Print
Print "Passed: " & TestsPassed & "   Failed: " & TestsFailed
If TestsFailed > 0 Then End 1
End 0
