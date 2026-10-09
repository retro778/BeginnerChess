'' =====================================================================
'' BeginnerChess - tests/test_engine.bas
'' Tests for the chess engine.
''
'' Usage:
''   test_engine            evaluation, tactics, mating, legality, threads
''   test_engine --bench    search speed benchmark
''   test_engine --match    short engine-vs-engine matches between levels
'' =====================================================================
#include once "../modules/game.bi"
#include once "../modules/engine.bi"

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

'' Mirrors a FEN: ranks reversed, colours swapped.
Function MirrorFEN(ByRef fen As Const String) As String
    Dim As String fields(0 To 5), cur = ""
    Dim As Integer n = 0, i
    For i = 1 To Len(fen) + 1
        Dim As String c = IIf(i <= Len(fen), Mid(fen, i, 1), " ")
        If c = " " Then
            If cur <> "" Then fields(n) = cur : n += 1 : cur = ""
        Else
            cur &= c
        End If
    Next
    '' Board
    Dim As String ranks(0 To 7), r = ""
    Dim As Integer k = 0
    For i = 1 To Len(fields(0)) + 1
        Dim As String c = IIf(i <= Len(fields(0)), Mid(fields(0), i, 1), "/")
        If c = "/" Then ranks(k) = r : k += 1 : r = "" Else r &= c
    Next
    Dim As String board = ""
    For i = 7 To 0 Step -1
        Dim As String swapped = "", j
        Dim As Integer q
        For q = 1 To Len(ranks(i))
            j = Mid(ranks(i), q, 1)
            If j >= "a" AndAlso j <= "z" Then
                swapped &= UCase(j)
            ElseIf j >= "A" AndAlso j <= "Z" Then
                swapped &= LCase(j)
            Else
                swapped &= j
            End If
        Next
        board &= swapped & IIf(i > 0, "/", "")
    Next
    Dim As String side = IIf(fields(1) = "w", "b", "w")
    Dim As String cr = ""
    If InStr(fields(2), "k") Then cr &= "K"
    If InStr(fields(2), "q") Then cr &= "Q"
    If InStr(fields(2), "K") Then cr &= "k"
    If InStr(fields(2), "Q") Then cr &= "q"
    If cr = "" Then cr = "-"
    Dim As String ep = fields(3)
    If ep <> "-" Then ep = Left(ep, 1) & Chr(Asc("1") + (Asc("8") - Asc(Mid(ep, 2, 1))))
    Return board & " " & side & " " & cr & " " & ep & " " & fields(4) & " " & fields(5)
End Function

Sub TestEvaluationSymmetry()
    Print "Evaluation symmetry..."
    Dim As String fens(0 To 7) = { START_FEN, _
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", _
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", _
        "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3", _
        "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", _
        "8/8/8/4k3/8/8/8/3QK3 w - - 0 1", _
        "6k1/5ppp/8/8/3P4/8/5PPP/6K1 b - - 0 1", _
        "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10" }
    Static p As Position, q As Position
    Dim As String errMsg
    Dim As Integer i
    For i = 0 To 7
        Dim As String m = MirrorFEN(fens(i))
        If Not Pos_LoadFEN(p, fens(i), errMsg) OrElse Not Pos_LoadFEN(q, m, errMsg) Then
            Check False, "mirror FEN loads", m & " " & errMsg
            Continue For
        End If
        Dim As Integer a = Engine_Evaluate(p), b = Engine_Evaluate(q)
        Check a = b, "eval(mirror) = eval  #" & i, a & " vs " & b & "  " & m
    Next
    Pos_SetStart(p)
    Check Abs(Engine_Evaluate(p)) <= 15, "start position is roughly equal", Str(Engine_Evaluate(p))
    Pos_LoadFEN(p, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR w KQkq - 0 1", errMsg)
    Check Engine_Evaluate(p) < -700, "missing queen is a big minus", Str(Engine_Evaluate(p))
    Pos_LoadFEN(p, "8/8/8/4k3/8/8/8/3NK3 w - - 0 1", errMsg)
    Check Abs(Engine_Evaluate(p)) < 60, "lone knight is scaled towards a draw", Str(Engine_Evaluate(p))
End Sub

Function SearchMove(ByRef fen As Const String, ByVal level As Integer, ByRef res As EngineResult, _
                    ByVal timeMs As Integer = 0) As Boolean
    Static p As Position
    Dim As String errMsg
    If Not Pos_LoadFEN(p, fen, errMsg) Then Return False
    Dim As EngineParams prm
    Engine_LevelParams(level, STYLE_BALANCED, prm)
    If timeMs > 0 Then prm.timeLimitMs = timeMs
    Return Engine_Search(p, prm, res)
End Function

'' Plays the engine's move and reports whether it is checkmate.
Function FindsMate(ByRef fen As Const String, ByVal level As Integer) As Boolean
    Static g As ChessGame
    Dim As String errMsg
    If Not Game_NewFromFEN(g, fen, errMsg) Then Return False
    Dim As EngineResult res
    If Not SearchMove(fen, level, res, 2000) Then Return False
    If Not Game_PlayMove(g, res.bestMove, errMsg) Then Return False
    Return g.termination = TERM_CHECKMATE
End Function

Sub TestTactics()
    Print "Tactics..."
    Dim As String mates(0 To 4) = { _
        "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", _
        "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2", _
        "k7/8/1K6/8/8/8/7Q/8 w - - 0 1", _
        "6rk/6pp/8/6N1/8/8/8/6K1 w - - 0 1", _
        "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 4 4" }
    Dim As Integer i, lvl
    For i = 0 To 4
        For lvl = LEVEL_NORMAL To LEVEL_ADVANCED Step 2
            Check FindsMate(mates(i), lvl), "mate in one #" & i & " (" & Engine_LevelName(lvl) & ")"
        Next
    Next
    Dim As EngineResult res
    SearchMove("4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1", LEVEL_NORMAL, res)
    Check Notation_MoveToUCI(res.bestMove) = "d1d5", "wins the hanging queen", Notation_MoveToUCI(res.bestMove)
    SearchMove("r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1", LEVEL_INTERMEDIATE, res)
    Check Notation_MoveToUCI(res.bestMove) = "b5c7", "knight fork Nc7+", Notation_MoveToUCI(res.bestMove)
    SearchMove("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", LEVEL_ADVANCED, res, 1000)
    Check res.score > SCORE_MATE - 10, "reports a mate score", Str(res.score)
    '' Defend against a back-rank mate threat: black threatens Rd1#.
    SearchMove("3r2k1/5ppp/8/8/8/8/5PPP/6K1 w - - 0 1", LEVEL_INTERMEDIATE, res)
    Dim As String mv = Notation_MoveToUCI(res.bestMove)
    Check mv = "h2h3" OrElse mv = "g2g3" OrElse mv = "f2f3" OrElse mv = "h2h4" OrElse mv = "g2g4" OrElse _
          mv = "f2f4" OrElse mv = "g1f1", "makes luft against back-rank mate", mv
End Sub

'' Engine plays both sides; returns the number of moves until mate (or -1).
Function SelfPlayMate(ByRef fen As Const String, ByVal maxMoves As Integer, ByVal timeMs As Integer) As Integer
    Static g As ChessGame
    Dim As String errMsg
    Game_NewFromFEN(g, fen, errMsg)
    Engine_NewGame()
    Dim As EngineParams prm
    Engine_LevelParams(LEVEL_ADVANCED, STYLE_BALANCED, prm)
    prm.timeLimitMs = timeMs
    Dim As Integer ply
    For ply = 1 To maxMoves * 2
        Dim As EngineResult res
        If Not Engine_Search(g.pos, prm, res) Then Exit For
        If Not Game_PlayMove(g, res.bestMove, errMsg) Then Return -1
        If g.termination = TERM_CHECKMATE Then Return (ply + 1) \ 2
        If Game_IsOver(g) Then Return -1
    Next
    Return -1
End Function

Sub TestMating()
    Print "Basic mates (engine vs engine)..."
    Dim As Integer n = SelfPlayMate("8/8/8/4k3/8/8/8/3QK3 w - - 0 1", 30, 300)
    Check n > 0, "K+Q mates a bare king", "moves: " & n
    n = SelfPlayMate("8/8/8/4k3/8/8/8/R3K3 w - - 0 1", 50, 300)
    Check n > 0, "K+R mates a bare king", "moves: " & n
End Sub

Sub TestLegality()
    Print "Legality fuzz (all levels and styles)..."
    Static p As Position
    Dim As MoveList list
    Dim As Integer games, ply, bad = 0, searches = 0
    Randomize 777
    For games = 1 To 12
        Pos_SetStart(p)
        For ply = 1 To 60
            Pos_GenerateLegal(p, list)
            If list.count = 0 Then Exit For
            If ply Mod 7 = 0 Then
                Dim As EngineParams prm
                Engine_LevelParams((games + ply) Mod LEVEL_COUNT, (games * 3 + ply) Mod STYLE_COUNT, prm)
                prm.timeLimitMs = 60
                Dim As EngineResult res
                Dim As String before = Pos_GetFEN(p)
                If Engine_Search(p, prm, res) Then
                    Dim As ChessMove chk
                    searches += 1
                    If Not Pos_FindLegalMove(p, res.bestMove.fromSq, res.bestMove.toSq, res.bestMove.promotion, chk) Then bad += 1
                    If Pos_GetFEN(p) <> before Then bad += 1
                End If
            End If
            Pos_MakeMove(p, list.moves(Int(Rnd * list.count)))
        Next
    Next
    Check bad = 0 AndAlso searches > 50, "engine always returns a legal move and leaves the position alone", _
          bad & " problems in " & searches & " searches"
    '' Only one legal move / no legal move
    Dim As EngineResult res
    Check SearchMove("7k/8/8/8/8/8/1q6/K7 w - - 0 1", LEVEL_ADVANCED, res) AndAlso _
          Notation_MoveToUCI(res.bestMove) = "a1b2", "single legal move (capture)", Notation_MoveToUCI(res.bestMove)
    Check SearchMove("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", LEVEL_NORMAL, res) = False, "no move in stalemate"
End Sub

Sub TestThreads()
    Print "Background thinking..."
    Static p As Position
    Pos_SetStart(p)
    Dim As EngineParams prm
    Engine_LevelParams(LEVEL_NORMAL, STYLE_BALANCED, prm)
    prm.timeLimitMs = 400
    Engine_StartAsync(p, prm)
    Check Engine_IsThinking(), "thinking after start"
    Dim As EngineResult res
    Dim As Double t0 = Timer
    Dim As Integer polls = 0
    Do Until Engine_PollAsync(res)
        polls += 1
        Sleep 5, 1
        If Timer - t0 > 10 Then Exit Do
    Loop
    Dim As ChessMove chk
    Check Pos_FindLegalMove(p, res.bestMove.fromSq, res.bestMove.toSq, res.bestMove.promotion, chk), _
          "async result is legal", Notation_MoveToUCI(res.bestMove)
    Check polls > 0, "main thread kept running while the engine thought", Str(polls)
    Check Not Engine_IsThinking(), "not thinking after the result was collected"

    '' Stop a long search early.
    Engine_LevelParams(LEVEL_ADVANCED, STYLE_BALANCED, prm)
    prm.timeLimitMs = 60000
    Engine_StartAsync(p, prm)
    Sleep 200, 1
    t0 = Timer
    Engine_StopAsync()
    Check Timer - t0 < 1.0, "a running search stops quickly", Str(Timer - t0)
    Check Not Engine_IsThinking(), "no thread left running"
End Sub

Sub TestBook()
    Print "Opening book..."
    Dim As Integer bad
    Dim As String firstErr
    Dim As Integer n = Book_Load(ExePath() & "/../data/openings/book.txt", bad, firstErr)
    Check n >= 70 AndAlso bad = 0, "book loads without errors", n & " lines, " & bad & " bad: " & firstErr
    Static g As ChessGame
    Dim As String errMsg
    Game_New(g)
    Check Book_MoveCount(g.pos) >= 5, "several first moves in the book", Str(Book_MoveCount(g.pos))
    Dim As String mv(0 To 5) = {"e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5"}
    Dim As Integer i
    For i = 0 To 5 : Game_PlayMoveText(g, mv(i), errMsg) : Next
    Check Book_OpeningName(g.pos) = "Italian Game", "opening name", Book_OpeningName(g.pos)
    Check Book_OpeningEco(g.pos) = "C50", "ECO code", Book_OpeningEco(g.pos)
    Dim As String naj(0 To 9) = {"e4", "c5", "Nf3", "d6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3", "a6"}
    Game_New(g)
    For i = 0 To 9 : Game_PlayMoveText(g, naj(i), errMsg) : Next
    Check Book_OpeningName(g.pos) = "Sicilian Defence: Najdorf Variation", "variation named before its line ends", _
          Book_OpeningName(g.pos)
    Game_New(g)
    For i = 0 To 3 : Game_PlayMoveText(g, naj(i), errMsg) : Next
    Check Book_OpeningName(g.pos) = "Sicilian Defence", "shared positions use the common name", Book_OpeningName(g.pos)
    Game_New(g)
    Check Book_OpeningName(g.pos) = "", "no name before any move"

    '' The engine uses the book and its choices vary.
    Dim As EngineParams prm
    Engine_LevelParams(LEVEL_ADVANCED, STYLE_BALANCED, prm)
    Dim As EngineResult res
    Dim As String seen = ""
    Dim As Integer distinct = 0, allBook = -1
    For i = 1 To 30
        Engine_Search(g.pos, prm, res)
        If Not res.fromBook Then allBook = 0
        Dim As String u = Notation_MoveToUCI(res.bestMove)
        If InStr(seen, u) = 0 Then seen &= u & " " : distinct += 1
    Next
    Check allBook <> 0, "first move comes from the book"
    Check distinct >= 2, "book gives variety", seen
    '' Beginners leave the book early.
    Engine_LevelParams(LEVEL_BEGINNER, STYLE_BALANCED, prm)
    Game_NewFromFEN(g, "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3", errMsg)
    Engine_Search(g.pos, prm, res)
    Check Not res.fromBook, "beginner does not use the book at move 3"
End Sub

Sub TestResign()
    Print "Resignation..."
    Static p As Position
    Dim As String errMsg
    Dim As Integer streak = 0
    Pos_LoadFEN(p, "4k3/8/8/8/8/8/3QQ3/4K3 b - - 0 1", errMsg)
    Check Engine_ShouldResign(p, -1500, streak) = False, "not after one bad move"
    Check Engine_ShouldResign(p, -1500, streak) = False, "not after two bad moves"
    Check Engine_ShouldResign(p, -1500, streak), "resigns after three hopeless moves"
    streak = 0
    Check Engine_ShouldResign(p, -SCORE_MATE + 9, streak), "resigns when mate is forced"
    streak = 5
    Check Engine_ShouldResign(p, -100, streak) = False AndAlso streak = 0, "a better position resets the count"
    '' Opponent cannot mate: never resign (it is a draw).
    Pos_LoadFEN(p, "4k3/8/8/8/8/8/3N4/4K3 b - - 0 1", errMsg)
    streak = 3
    Check Engine_ShouldResign(p, -SCORE_MATE + 9, streak) = False, "never resigns when the opponent cannot mate"
End Sub

Sub Bench()
    Dim As String fens(0 To 2) = { START_FEN, _
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", _
        "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10" }
    Dim As Integer i
    For i = 0 To 2
        Dim As EngineResult res
        Engine_NewGame()
        SearchMove(fens(i), LEVEL_ADVANCED, res, 3000)
        Dim As String pvText = ""
        Dim As Integer j
        For j = 0 To res.pvLen - 1
            pvText &= Notation_MoveToUCI(res.pv(j)) & " "
        Next
        Print "depth " & res.depth & "  score " & res.score & "  nodes " & res.nodes & "  " & _
              res.timeMs & " ms  " & CLngInt(res.nodes / (res.timeMs / 1000 + 0.001)) & " n/s  pv " & pvText
    Next
End Sub

'' Plays games between two levels; returns points of level A (win 1, draw 0.5).
Function Match(ByVal levelA As Integer, ByVal levelB As Integer, ByVal games As Integer, ByVal timeMs As Integer) As Single
    Static g As ChessGame
    Dim As Single points = 0
    Dim As Integer gi
    For gi = 1 To games
        Game_New(g)
        Engine_NewGame()
        Dim As Integer aSide = IIf(gi Mod 2 = 1, SIDE_WHITE, SIDE_BLACK)
        Dim As String errMsg
        Do While Not Game_IsOver(g) AndAlso g.moveCount < 300
            If Game_ClaimableDraw(g) <> TERM_NONE Then Game_ClaimDraw(g) : Exit Do
            Dim As EngineParams prm
            Engine_LevelParams(IIf(g.pos.sideToMove = aSide, levelA, levelB), STYLE_BALANCED, prm)
            prm.timeLimitMs = timeMs
            Dim As EngineResult res
            Engine_Search(g.pos, prm, res)
            Game_PlayMove(g, res.bestMove, errMsg)
        Loop
        Dim As Single pts = 0.5
        If g.result = RESULT_WHITE_WINS Then pts = IIf(aSide = SIDE_WHITE, 1, 0)
        If g.result = RESULT_BLACK_WINS Then pts = IIf(aSide = SIDE_BLACK, 1, 0)
        points += pts
        Print "  game " & gi & ": " & Engine_LevelName(levelA) & " (" & IIf(aSide = SIDE_WHITE, "White", "Black") & _
              ") scores " & pts & "   " & Game_ResultString(g) & " in " & g.moveCount & " plies"
    Next
    Return points
End Function

'' ---------------------------------------------------------------------
Select Case Command(1)
Case "--bench"
    Bench()
    End 0
Case "--match"
    Dim As Single pts
    pts = Match(LEVEL_NORMAL, LEVEL_BEGINNER, 4, 300)
    Print "Normal vs Beginner: " & pts & " / 4"
    pts = Match(LEVEL_ADVANCED, LEVEL_EASY, 2, 300)
    Print "Advanced vs Easy: " & pts & " / 2"
    End 0
End Select

Print "BeginnerChess engine tests"
Engine_NewGame()
TestEvaluationSymmetry()
TestTactics()
TestMating()
TestLegality()
TestThreads()
TestBook()
TestResign()
Engine_Shutdown()
Print
Print "Passed: " & TestsPassed & "   Failed: " & TestsFailed
If TestsFailed > 0 Then End 1
End 0
