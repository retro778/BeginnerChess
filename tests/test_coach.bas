'' =====================================================================
'' BeginnerChess - tests/test_coach.bas
'' Tests for the coach (explanations, exchanges, threats) and game review.
'' =====================================================================
#include once "../modules/coach.bi"
#include once "../modules/analysis.bi"

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

Function Explain(ByRef fen As Const String, ByRef san As Const String) As String
    Static p As Position
    Dim As String e
    If Not Pos_LoadFEN(p, fen, e) Then Return "BAD FEN " & e
    Dim As ChessMove m
    If Not Notation_ParseSAN(p, san, m, e) Then Return "BAD MOVE " & e
    Return Coach_ExplainMove(p, m)
End Function

Function SeeOf(ByRef fen As Const String, ByRef san As Const String) As Integer
    Static p As Position
    Dim As String e
    Pos_LoadFEN(p, fen, e)
    Dim As ChessMove m
    Notation_ParseSAN(p, san, m, e)
    Return Coach_SEE(p, m)
End Function

Sub TestExchanges()
    Print "Exchanges and threats..."
    Check SeeOf("4k3/8/4p3/3n4/2P5/8/8/4K3 w - - 0 1", "cxd5") = 200, "pawn takes defended knight: +200", Str(SeeOf("4k3/8/4p3/3n4/2P5/8/8/4K3 w - - 0 1", "cxd5"))
    Check SeeOf("4k3/8/4p3/3p4/8/8/3Q4/4K3 w - - 0 1", "Qxd5") = -800, "queen takes defended pawn: -800"
    Check SeeOf("4k3/8/8/3p4/8/8/3Q4/4K3 w - - 0 1", "Qxd5") = 100, "queen takes free pawn: +100"
    Check SeeOf("4k3/8/4p3/3p4/8/3R4/3R4/4K3 w - - 0 1", "Rxd5") = -300, "rook takes a pawn defended by a pawn: -300", Str(SeeOf("4k3/8/4p3/3p4/8/3R4/3R4/4K3 w - - 0 1", "Rxd5"))
    Static p As Position
    Dim As String e
    Pos_LoadFEN(p, "4k3/8/8/4p3/3N4/8/8/4K3 w - - 0 1", e)
    Check Coach_ThreatOn(p, Sq_Parse("d4")) > 0, "knight attacked by a pawn is threatened"
    Pos_LoadFEN(p, "4k3/8/8/3q4/3N4/4P3/8/4K3 w - - 0 1", e)
    Check Coach_ThreatOn(p, Sq_Parse("d4")) = 0, "knight defended by a pawn and attacked by the queen is safe"
    Dim As Integer res(0 To 127)
    Pos_LoadFEN(p, "rnbqkbnr/ppp1ppp1/7p/3p2B1/3P4/8/PPP1PPPP/RN1QKBNR w KQkq - 0 3", e)
    Coach_ThreatenedPieces(p, SIDE_WHITE, res())
    Check res(Sq_Parse("g5")) > 0 AndAlso res(Sq_Parse("d4")) = 0, "threatened bishop found"
End Sub

Sub TestExplanations()
    Print "Explanations..."
    Dim As String s
    s = Explain("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", "Rd8#")
    Check InStr(s, "checkmate") > 0, "mate", s
    s = Explain("k7/8/8/7n/8/8/8/3QK3 w - - 0 1", "Qxh5")
    Check InStr(s, "not protected") > 0, "free piece", s
    s = Explain("r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1", "Nc7+")
    Check InStr(s, "fork") > 0 AndAlso InStr(s, "rook") > 0, "check fork", s
    s = Explain("8/8/2k1q3/8/8/5N2/8/7K w - - 0 1", "Nd4+")
    Check InStr(s, "fork") > 0 AndAlso InStr(s, "queen") > 0, "royal fork", s
    s = Explain("rnbqkbnr/ppp1ppp1/7p/3p2B1/3P4/8/PPP1PPPP/RN1QKBNR w KQkq - 0 3", "Bf4")
    Check InStr(s, "under attack") > 0 AndAlso InStr(s, "g5") > 0, "save the attacked bishop", s
    s = Explain("r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3", "g6")
    Check InStr(s, "stops") > 0, "stop a mate threat", s
    s = Explain("r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4", "O-O")
    Check InStr(s, "Castle") > 0, "castling", s
    s = Explain("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2", "Nf3")
    Check InStr(s, "Develop your knight") > 0, "development", s
    s = Explain(START_FEN, "d4")
    Check InStr(s, "centre") > 0, "central pawn", s
    s = Explain("r4rk1/pp3ppp/2n1bn2/8/8/2N1BN2/PP3PPP/R4RK1 w - - 0 14", "Rfd1")
    Check InStr(s, "open d-file") > 0, "open file", s
    s = Explain("8/8/8/3P4/8/5k2/8/3K4 w - - 0 1", "d6")
    Check InStr(s, "passed pawn") > 0, "passed pawn", s
    s = Explain("7k/1P6/8/8/8/8/8/4K3 w - - 0 1", "b8=Q+")
    Check InStr(s, "Promote") > 0 OrElse InStr(s, "Give check") > 0, "promotion", s
    '' Threat after a blunder: Nf6?? allows Qxf7#
    Static p As Position
    Dim As String e
    Pos_LoadFEN(p, "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", e)
    Dim As ChessMove m
    Notation_ParseSAN(p, "Qxf7#", m, e)
    s = Coach_ExplainThreat(p, m)
    Check InStr(s, "checkmate you") > 0, "threat description", s
    Check Coach_EvalText(0) = "The position is about equal." AndAlso InStr(Coach_EvalText(250), "White is better") > 0 _
          AndAlso InStr(Coach_EvalText(-1200), "Black is winning") > 0, "evaluation in words", Coach_EvalText(-1200)
End Sub

Sub TestReview()
    Print "Game review..."
    Check Analysis_Classify(1, False) = MC_BEST AndAlso Analysis_Classify(5, False) = MC_GOOD AndAlso _
          Analysis_Classify(10, False) = MC_INACCURACY AndAlso Analysis_Classify(18, False) = MC_MISTAKE AndAlso _
          Analysis_Classify(40, False) = MC_BLUNDER, "classification thresholds"
    Check Abs(Analysis_WinChance(0) - 50) < 0.01 AndAlso Analysis_WinChance(400) > 85, "winning chance curve"
    Static g As ChessGame
    Dim As String e
    Game_New(g)
    Dim As String mv(0 To 6) = {"e4", "e5", "Qh5", "Nc6", "Bc4", "Nf6", "Qxf7#"}
    Dim As Integer i
    For i = 0 To 6 : Game_PlayMoveText(g, mv(i), e) : Next
    Analysis_Begin(g, 150)
    Dim As Integer steps = 0
    Do Until Analysis_Step()
        steps += 1
        If steps > 20 Then Exit Do
    Loop
    Check Analysis_Done() AndAlso Analysis_Progress() = 100, "analysis finishes"
    Check Analysis_Class(5) = MC_BLUNDER, "3...Nf6?? is a blunder", Analysis_ClassName(Analysis_Class(5))
    Check Analysis_Class(6) = MC_BEST, "4.Qxf7# is best", Analysis_ClassName(Analysis_Class(6))
    Check Analysis_Class(0) = MC_BOOK, "1.e4 is a book move", Analysis_ClassName(Analysis_Class(0))
    Dim As ChessMove bm = Analysis_BestMove(5)
    Static p As Position
    Analysis_PositionBefore(5, p)
    Dim As String bestSan = Notation_MoveToSAN(p, bm)
    Check bestSan <> "Nf6", "a better move than Nf6 is suggested", bestSan
    Check Analysis_WhiteScore(6) >= 3000, "after mate the score is decisive", Str(Analysis_WhiteScore(6))
End Sub

Print "BeginnerChess coach and review tests"
Scope
    Dim As Integer bad
    Dim As String err1
    Book_Load(ExePath() & "/../data/openings/book.txt", bad, err1)
End Scope
TestExchanges()
TestExplanations()
TestReview()
Print
Print "Passed: " & TestsPassed & "   Failed: " & TestsFailed
If TestsFailed > 0 Then End 1
End 0
