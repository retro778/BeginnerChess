'' =====================================================================
'' BeginnerChess - tests/test_core.bas
'' Tests for the chess core: rules, FEN, SAN, game status and perft.
''
'' Usage:
''   test_core                 unit tests + quick perft suite
''   test_core --full          unit tests + deeper perft suite (slower)
''   test_core --perft "<fen>" <depth>
''   test_core --divide "<fen>" <depth>   per-move counts for debugging
'' =====================================================================
#include once "../modules/game.bi"

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

'' Plays a space-separated list of moves; returns False at the first illegal one.
Function PlayMoves(ByRef g As ChessGame, ByRef moves As Const String) As Boolean
    Dim As String rest = Trim(moves) & " ", errMsg
    Do While Len(Trim(rest)) > 0
        Dim As Integer sp = InStr(rest, " ")
        Dim As String mv = Left(rest, sp - 1)
        rest = LTrim(Mid(rest, sp + 1))
        If Not Game_PlayMoveText(g, mv, errMsg) Then
            Print "    could not play '" & mv & "': " & errMsg
            Return False
        End If
    Loop
    Return True
End Function

Function LegalCount(ByRef fen As Const String) As Integer
    Static p As Position
    Dim As String errMsg
    If Not Pos_LoadFEN(p, fen, errMsg) Then Return -1
    Dim As MoveList list
    Pos_GenerateLegal(p, list)
    Return list.count
End Function

Function HasLegalSAN(ByRef fen As Const String, ByRef san As Const String) As Boolean
    Static p As Position
    Dim As String errMsg
    If Not Pos_LoadFEN(p, fen, errMsg) Then Return False
    Dim As ChessMove m
    Return Notation_ParseSAN(p, san, m, errMsg)
End Function

'' ---------------------------------------------------------------------
'' Unit tests
'' ---------------------------------------------------------------------
Sub TestFEN()
    Print "FEN..."
    Static p As Position
    Dim As String errMsg
    Check Pos_LoadFEN(p, START_FEN, errMsg), "load start FEN", errMsg
    Check Pos_GetFEN(p) = START_FEN, "start FEN round trip", Pos_GetFEN(p)

    Dim As String kiwi = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
    Check Pos_LoadFEN(p, kiwi, errMsg) AndAlso Pos_GetFEN(p) = kiwi, "Kiwipete round trip"

    Dim As String epFen = "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3"
    Check Pos_LoadFEN(p, epFen, errMsg) AndAlso Pos_GetFEN(p) = epFen, "en-passant FEN round trip"

    Check Pos_LoadFEN(p, "8/8/8/8/8/8/8/8 w - - 0 1", errMsg) = False, "reject: no kings"
    Check Pos_LoadFEN(p, "rnbqkbnr/ppppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", errMsg) = False, "reject: 9 squares"
    Check Pos_LoadFEN(p, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1", errMsg) = False, "reject: 7 ranks"
    Check Pos_LoadFEN(p, "rnbqkbnr/ppxppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", errMsg) = False, "reject: bad letter"
    Check Pos_LoadFEN(p, "P3k3/8/8/8/8/8/8/4K3 w - - 0 1", errMsg) = False, "reject: pawn on 8th rank"
    Check Pos_LoadFEN(p, "4k3/4R3/8/8/8/8/8/4K3 w - - 0 1", errMsg) = False, "reject: side not to move in check"
    Check Pos_LoadFEN(p, "4k3/8/8/8/8/8/8/4K3 x - - 0 1", errMsg) = False, "reject: bad side to move"
    Check Pos_LoadFEN(p, "hello", errMsg) = False, "reject: garbage"

    '' A bad FEN must leave the previous position untouched.
    Pos_LoadFEN(p, START_FEN, errMsg)
    Pos_LoadFEN(p, "garbage w - - 0 1", errMsg)
    Check Pos_GetFEN(p) = START_FEN, "bad FEN leaves position unchanged"

    '' Castling rights inconsistent with the pieces are dropped.
    Check Pos_LoadFEN(p, "4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1", errMsg) AndAlso _
          Pos_GetFEN(p) = "4k3/8/8/8/8/8/8/4K3 w - - 0 1", "impossible castling rights dropped"

    '' Short FEN (4 fields) gets default counters.
    Check Pos_LoadFEN(p, "4k3/8/8/8/8/8/8/4K3 w - -", errMsg) AndAlso _
          Pos_GetFEN(p) = "4k3/8/8/8/8/8/8/4K3 w - - 0 1", "4-field FEN accepted"
End Sub

Sub TestMakeUnmakeAndHash()
    Print "Make/unmake and hashing..."
    Static p As Position
    Dim As String errMsg
    Dim As MoveList list
    Dim As Integer game, ply, okHash = -1, okRestore = -1
    Randomize 12345
    Dim As String fens(0 To 2) = { START_FEN, _
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", _
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1" }
    For game = 0 To 29
        Dim As String startFen = fens(game Mod 3)
        Pos_LoadFEN(p, startFen, errMsg)
        For ply = 1 To 150
            Pos_GenerateLegal(p, list)
            If list.count = 0 Then Exit For
            Pos_MakeMove(p, list.moves(Int(Rnd * list.count)))
            If p.hash <> Pos_ComputeHash(p) Then okHash = 0
        Next
        Do While p.historyCount > 0
            Pos_UnmakeMove(p)
            If p.hash <> Pos_ComputeHash(p) Then okHash = 0
        Loop
        If Pos_GetFEN(p) <> startFen Then okRestore = 0
    Next
    Check okHash <> 0, "incremental hash equals recomputed hash (random games)"
    Check okRestore <> 0, "unmaking all moves restores the start position"

    '' Same position reached by different move orders => same hash.
    Static g1 As ChessGame, g2 As ChessGame
    Game_New(g1) : Game_New(g2)
    PlayMoves(g1, "e4 e5 Nf3 Nc6")
    PlayMoves(g2, "Nf3 Nc6 e4 e5")
    '' e2-e4 / e7-e5 leave en-passant squares, but they are not capturable,
    '' so they must not affect the hash.
    Check g1.pos.hash = g2.pos.hash, "transposition gives same hash"
End Sub

Sub TestRulesPositions()
    Print "Special rules..."
    Static p As Position
    Dim As String errMsg

    '' Castling
    Check LegalCount("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1") = 26, "castling: both sides available (26 moves)"
    Check HasLegalSAN("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "O-O"), "castling: O-O legal"
    Check HasLegalSAN("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "O-O-O"), "castling: O-O-O legal"
    Check HasLegalSAN("4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1", "O-O") = False, "castling: not through attacked f1"
    Check HasLegalSAN("4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1", "O-O-O"), "castling: queenside still legal"
    Check HasLegalSAN("4k1r1/8/8/8/8/8/8/R3K2R w KQ - 0 1", "O-O") = False, "castling: not into check (g1)"
    Check HasLegalSAN("1r2k3/8/8/8/8/8/8/R3K2R w KQ - 0 1", "O-O-O"), "castling: attacked b1 does not matter"
    Check HasLegalSAN("4r1k1/8/8/8/8/8/8/R3K2R w KQ - 0 1", "O-O") = False, "castling: not out of check (O-O)"
    Check HasLegalSAN("4r1k1/8/8/8/8/8/8/R3K2R w KQ - 0 1", "O-O-O") = False, "castling: not out of check (O-O-O)"
    Check HasLegalSAN("r3k2r/8/8/8/8/8/8/RN2K2R w KQkq - 0 1", "O-O-O") = False, "castling: blocked by knight"

    Static g As ChessGame
    Game_NewFromFEN(g, "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", errMsg)
    PlayMoves(g, "Rxa8+")
    Check InStr(Pos_GetFEN(g.pos), " b Kk ") > 0, "capturing a rook removes castling rights", Pos_GetFEN(g.pos)
    Game_NewFromFEN(g, "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", errMsg)
    PlayMoves(g, "Kf1")
    Check InStr(Pos_GetFEN(g.pos), " b kq ") > 0, "moving the king removes castling rights", Pos_GetFEN(g.pos)
    Game_NewFromFEN(g, "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", errMsg)
    PlayMoves(g, "O-O")
    Check Pos_GetFEN(g.pos) = "r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1", "O-O places king and rook", Pos_GetFEN(g.pos)
    Game_Undo(g)
    Check Pos_GetFEN(g.pos) = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "undo O-O"

    '' En passant
    Game_NewFromFEN(g, "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", errMsg)
    Check PlayMoves(g, "exd6"), "en passant: exd6 legal"
    Check Pos_GetFEN(g.pos) = "4k3/8/3P4/8/8/8/8/4K3 b - - 0 1", "en passant removes the captured pawn", Pos_GetFEN(g.pos)
    Check g.sanMoves(0) = "exd6", "en passant SAN", g.sanMoves(0)
    Check HasLegalSAN("8/8/8/K2pP2r/8/8/8/7k w - d6 0 1", "exd6") = False, "en passant: illegal when it exposes the king"
    Check HasLegalSAN("4k3/8/8/3pP3/8/8/8/4K3 w - - 0 1", "exd6") = False, "en passant: only right after the double step"
    Game_New(g)
    PlayMoves(g, "e4 a6 e5 d5")
    Check PlayMoves(g, "exd6"), "en passant in a played game"

    '' Promotion
    Game_NewFromFEN(g, "8/P7/8/8/8/8/8/k6K w - - 0 1", errMsg)
    Check LegalCount("8/P7/8/8/8/8/8/k6K w - - 0 1") = 7, "promotion: 4 promotions + 3 king moves"
    Check Game_PlayMoveText(g, "a8", errMsg) = False, "promotion: piece must be chosen"
    Check PlayMoves(g, "a8=N"), "promotion: underpromotion to knight"
    Check g.pos.board(SQ_A8) = PC_WN, "promotion: knight on a8"
    Game_Undo(g)
    Check g.pos.board(MAKE_SQ(0, 6)) = PC_WP AndAlso g.pos.board(SQ_A8) = PC_EMPTY, "promotion: undo restores pawn"
    PlayMoves(g, "a7a8q")
    Check g.sanMoves(0) = "a8=Q+", "promotion SAN with check", g.sanMoves(0)
    Check HasLegalSAN("1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1", "axb8=Q+"), "promotion with capture"

    '' Pins
    Check LegalCount("4k3/4r3/8/8/8/8/4B3/4K3 w - - 0 1") = 4, "pinned bishop cannot move"
    Check HasLegalSAN("4k3/4r3/8/8/8/8/4R3/4K3 w - - 0 1", "Rxe7+"), "pinned rook may capture the pinner"

    '' Double check: only king moves are legal.
    Pos_LoadFEN(p, "4r1k1/8/8/8/1b6/8/2N5/4K3 w - - 0 1", errMsg)
    Check Pos_CountCheckers(p) = 2, "double check detected"
    Dim As MoveList list
    Pos_GenerateLegal(p, list)
    Dim As Integer i, onlyKing = -1
    For i = 0 To list.count - 1
        If PIECE_TYPE(list.moves(i).piece) <> PT_KING Then onlyKing = 0
    Next
    Check onlyKing <> 0 AndAlso list.count > 0, "double check: only king moves"
End Sub

Sub TestGameEnd()
    Print "Game endings..."
    Static g As ChessGame
    Dim As String errMsg

    '' Fool's mate
    Game_New(g)
    Check PlayMoves(g, "f3 e5 g4 Qh4#"), "fool's mate moves"
    Check g.termination = TERM_CHECKMATE AndAlso g.result = RESULT_BLACK_WINS, "fool's mate is checkmate"
    Check g.sanMoves(3) = "Qh4#", "mate SAN suffix", g.sanMoves(3)
    Check Game_MoveListText(g) = "1. f3 e5 2. g4 Qh4#", "move list text", Game_MoveListText(g)
    Check Game_ResultString(g) = "0-1", "result string"
    Check Game_PlayMoveText(g, "a3", errMsg) = False, "no moves after game over"
    Game_Undo(g)
    Check Game_IsOver(g) = False, "undo reopens the game"

    '' Stalemate
    Check Game_NewFromFEN(g, "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", errMsg) AndAlso _
          g.termination = TERM_STALEMATE, "stalemate detected"
    Game_NewFromFEN(g, "7k/8/6K1/8/8/8/8/5Q2 w - - 0 1", errMsg)
    PlayMoves(g, "Qf7")
    Check g.termination = TERM_STALEMATE AndAlso g.result = RESULT_DRAW, "stalemate after a move"

    '' Insufficient material
    Check Game_NewFromFEN(g, "8/8/8/4k3/8/8/8/4K3 w - - 0 1", errMsg) AndAlso g.termination = TERM_INSUFFICIENT, "K v K"
    Check Game_NewFromFEN(g, "8/8/8/4k3/8/8/8/4KN2 w - - 0 1", errMsg) AndAlso g.termination = TERM_INSUFFICIENT, "KN v K"
    Check Game_NewFromFEN(g, "8/8/8/4k3/8/8/8/4KB2 w - - 0 1", errMsg) AndAlso g.termination = TERM_INSUFFICIENT, "KB v K"
    Check Game_NewFromFEN(g, "8/8/8/4k3/5b2/8/8/2B1K3 w - - 0 1", errMsg) AndAlso g.termination = TERM_INSUFFICIENT, "KB v KB same colour"
    Check Game_NewFromFEN(g, "8/8/8/4kb2/8/8/8/2B1K3 w - - 0 1", errMsg) AndAlso g.termination = TERM_NONE, "KB v KB opposite colours is playable"
    Check Game_NewFromFEN(g, "8/8/8/4k3/8/8/8/3NKN2 w - - 0 1", errMsg) AndAlso g.termination = TERM_NONE, "KNN v K is playable"
    Check Game_NewFromFEN(g, "8/8/8/4k3/8/8/4P3/4K3 w - - 0 1", errMsg) AndAlso g.termination = TERM_NONE, "KP v K is playable"
    Game_NewFromFEN(g, "8/8/8/4k3/8/8/8/2n1K3 w - - 0 1", errMsg)
    Check g.termination = TERM_INSUFFICIENT, "K v KN"
    Game_NewFromFEN(g, "8/8/8/4k3/8/8/8/1Rn1K3 b - - 0 1", errMsg)
    PlayMoves(g, "Nd3+ Kd2 Nb2 Rxb2")
    Check g.termination = TERM_NONE, "K+R v K is playable"

    '' Threefold repetition (claimable) and fivefold (automatic)
    Game_New(g)
    PlayMoves(g, "Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1")
    Check Game_ClaimableDraw(g) = TERM_NONE, "not yet threefold"
    Dim As ChessMove m
    Notation_ParseMove(g.pos, "Ng8", m, errMsg)
    Check Game_ClaimableDrawWithMove(g, m) = TERM_THREEFOLD, "threefold claimable with intended move"
    PlayMoves(g, "Ng8")
    Check Game_IsOver(g) = False, "threefold does not end the game by itself"
    Check Game_ClaimableDraw(g) = TERM_THREEFOLD, "threefold claimable"
    Check Game_ClaimHint(g) <> "", "claim hint text"
    PlayMoves(g, "e3")
    Check Game_ClaimableDraw(g) = TERM_NONE, "no claim in a new position"
    Game_Undo(g)
    '' The start position occurs at plies 0, 4, 8, 12 and 16.
    PlayMoves(g, "Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1")
    Check Game_IsOver(g) = False, "four times is not yet automatic"
    PlayMoves(g, "Ng8")
    Check g.termination = TERM_FIVEFOLD AndAlso g.result = RESULT_DRAW, "fivefold repetition is automatic"

    Game_New(g)
    PlayMoves(g, "Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1 Ng8")
    Check Game_ClaimDraw(g) AndAlso g.termination = TERM_THREEFOLD AndAlso g.result = RESULT_DRAW, "claim threefold"
    Game_Undo(g)
    Check Game_IsOver(g) = False AndAlso g.moveCount = 8, "undo a claimed draw keeps the moves"

    Game_New(g)
    PlayMoves(g, "Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1")
    Notation_ParseMove(g.pos, "Ng8", m, errMsg)
    Check Game_ClaimDrawWithMove(g, m, errMsg) AndAlso g.termination = TERM_THREEFOLD AndAlso _
          g.moveCount = 8, "claim threefold with intended move"
    Game_New(g)
    Notation_ParseMove(g.pos, "e4", m, errMsg)
    Check Game_ClaimDrawWithMove(g, m, errMsg) = False AndAlso g.moveCount = 0, "false claim rejected"

    '' A different en-passant possibility makes positions different.
    Game_NewFromFEN(g, "4k3/8/8/8/4p3/8/3P4/4K2N w - - 0 1", errMsg)
    PlayMoves(g, "d4 Kd7 Ng3 Ke8 Nh1 Kd7 Ng3 Ke8 Nh1")
    Check Game_ClaimableDraw(g) = TERM_NONE, "en-passant chance makes the first position different"
    '' The position after 1...Kd7 now occurs for the third time.
    PlayMoves(g, "Kd7")
    Check Game_ClaimableDraw(g) = TERM_THREEFOLD, "threefold after en-passant chance expired"

    '' Fifty-move rule (claimable) and 75-move rule (automatic)
    Game_NewFromFEN(g, "8/8/8/4k3/8/8/R7/4K3 w - - 99 80", errMsg)
    Check Game_ClaimableDraw(g) = TERM_NONE, "99 half-moves: no claim yet"
    Notation_ParseMove(g.pos, "Ra3", m, errMsg)
    Check Game_ClaimableDrawWithMove(g, m) = TERM_FIFTY_MOVE, "fifty-move claim with intended move"
    PlayMoves(g, "Ra3")
    Check Game_IsOver(g) = False AndAlso Game_ClaimableDraw(g) = TERM_FIFTY_MOVE, "fifty-move rule is claimable"
    Game_NewFromFEN(g, "8/8/8/4k3/8/8/R7/4K3 w - - 149 100", errMsg)
    PlayMoves(g, "Ra3")
    Check g.termination = TERM_SEVENTY_FIVE_MOVE, "75-move rule is automatic"

    '' Mate takes priority over the move-count rules.
    Game_NewFromFEN(g, "7k/8/6K1/8/8/8/8/R7 w - - 149 100", errMsg)
    Notation_ParseMove(g.pos, "Ra8", m, errMsg)
    Check Game_ClaimableDrawWithMove(g, m) = TERM_NONE, "no draw claim with a mating move"
    PlayMoves(g, "Ra8#")
    Check g.termination = TERM_CHECKMATE, "checkmate beats the 75-move rule"

    '' Resignation and agreement
    Game_New(g)
    Game_Resign(g, SIDE_WHITE)
    Check g.result = RESULT_BLACK_WINS AndAlso g.termination = TERM_RESIGNATION, "resignation"
    Game_Undo(g)
    Check Game_IsOver(g) = False, "undo resignation"
    Game_AgreeDraw(g)
    Check g.result = RESULT_DRAW AndAlso g.termination = TERM_AGREEMENT, "draw by agreement"
End Sub

Sub TestSAN()
    Print "Notation..."
    Static g As ChessGame
    Static p As Position
    Dim As String errMsg
    Dim As ChessMove m

    Pos_SetStart(p)
    Check Notation_ParseMove(p, "Nf3", m, errMsg) AndAlso Notation_MoveToUCI(m) = "g1f3", "parse Nf3"
    Check Notation_ParseMove(p, "nf3", m, errMsg) AndAlso Notation_MoveToUCI(m) = "g1f3", "parse lowercase nf3"
    Check Notation_ParseMove(p, "g1f3", m, errMsg) AndAlso Notation_MoveToSAN(p, m) = "Nf3", "parse coordinates g1f3"
    Check Notation_ParseMove(p, "Ng1-f3", m, errMsg), "parse long algebraic Ng1-f3"
    Check Notation_ParseMove(p, "e4!?", m, errMsg), "parse with annotation"
    Check Notation_ParseMove(p, "e5", m, errMsg) = False, "reject e5 for white"
    Check Notation_ParseMove(p, "Ke2", m, errMsg) = False, "reject Ke2"
    Check Notation_ParseMove(p, "O-O", m, errMsg) = False, "reject early castling"
    Check Notation_ParseMove(p, "e2e5", m, errMsg) = False, "reject e2e5"
    Check Notation_ParseMove(p, "xyz", m, errMsg) = False, "reject nonsense"

    '' Disambiguation by rank and by file
    Pos_LoadFEN(p, "7k/8/8/R7/8/8/8/R5K1 w - - 0 1", errMsg)
    Check Notation_ParseSAN(p, "Ra3", m, errMsg) = False, "ambiguous Ra3 rejected"
    Check Notation_ParseSAN(p, "R1a3", m, errMsg) AndAlso Notation_MoveToSAN(p, m) = "R1a3", "SAN R1a3"
    Pos_LoadFEN(p, "7k/8/8/8/8/8/8/1N3NK1 w - - 0 1", errMsg)
    Check Notation_ParseSAN(p, "Nbd2", m, errMsg) AndAlso Notation_MoveToSAN(p, m) = "Nbd2", "SAN Nbd2"
    '' Three queens: needs full square
    Pos_LoadFEN(p, "7k/8/8/8/Q1Q5/8/Q7/1K6 w - - 0 1", errMsg)
    Check Notation_ParseSAN(p, "Qa4b3", m, errMsg) AndAlso Notation_MoveToSAN(p, m) = "Qa4b3", "SAN Qa4b3", Notation_MoveToSAN(p, m)

    '' bxc3 (pawn) vs Bxc3 (bishop)
    Pos_LoadFEN(p, "4k3/8/8/8/8/2n5/1P1B4/4K3 w - - 0 1", errMsg)
    Check Notation_ParseSAN(p, "bxc3", m, errMsg) AndAlso PIECE_TYPE(m.piece) = PT_PAWN, "bxc3 is a pawn capture"
    Check Notation_ParseSAN(p, "Bxc3", m, errMsg) AndAlso PIECE_TYPE(m.piece) = PT_BISHOP, "Bxc3 is a bishop capture"

    '' Castling with zeros
    Game_NewFromFEN(g, "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", errMsg)
    Check PlayMoves(g, "0-0 0-0-0"), "castling written with zeros"
    Check g.sanMoves(0) = "O-O" AndAlso g.sanMoves(1) = "O-O-O", "castling SAN"

    '' A full game with SAN round trip: every recorded SAN must parse back.
    Game_New(g)
    Dim As String moves = "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3 Nb8 d4 Nbd7"
    Check PlayMoves(g, moves), "Ruy Lopez line plays"
    Check Game_MoveListText(g) = "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7", _
          "Ruy Lopez move list", Game_MoveListText(g)

    '' Move list starting with Black
    Game_NewFromFEN(g, "4k3/8/8/8/8/8/8/R3K3 b Q - 0 12", errMsg)
    PlayMoves(g, "Kd7 O-O-O+")
    Check Game_MoveListText(g) = "12... Kd7 13. O-O-O+", "move list starting with black", Game_MoveListText(g)
End Sub

'' ---------------------------------------------------------------------
'' Perft
'' ---------------------------------------------------------------------
Type PerftCase
    fen   As String
    depth As Integer
    nodes As ULongInt
End Type

Dim Shared PerftCases(0 To 99) As PerftCase
Dim Shared PerftCount As Integer = 0

Sub AddPerft(ByRef fen As Const String, ByVal depth As Integer, ByVal nodes As ULongInt)
    PerftCases(PerftCount).fen = fen
    PerftCases(PerftCount).depth = depth
    PerftCases(PerftCount).nodes = nodes
    PerftCount += 1
End Sub

Sub BuildPerftSuite(ByVal full As Boolean)
    '' Reference values from the Chess Programming Wiki "Perft Results"
    '' page and widely used perft test collections.
    Const KIWI = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
    Const POS3 = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
    Const POS4 = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
    Const POS4M = "r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1"
    Const POS5 = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"
    Const POS6 = "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10"

    AddPerft(START_FEN, 1, 20)
    AddPerft(START_FEN, 2, 400)
    AddPerft(START_FEN, 3, 8902)
    AddPerft(START_FEN, 4, 197281)
    AddPerft(KIWI, 1, 48)
    AddPerft(KIWI, 2, 2039)
    AddPerft(KIWI, 3, 97862)
    AddPerft(POS3, 1, 14)
    AddPerft(POS3, 2, 191)
    AddPerft(POS3, 3, 2812)
    AddPerft(POS3, 4, 43238)
    AddPerft(POS3, 5, 674624)
    AddPerft(POS4, 1, 6)
    AddPerft(POS4, 2, 264)
    AddPerft(POS4, 3, 9467)
    AddPerft(POS4M, 3, 9467)
    AddPerft(POS5, 1, 44)
    AddPerft(POS5, 2, 1486)
    AddPerft(POS5, 3, 62379)
    AddPerft(POS6, 1, 46)
    AddPerft(POS6, 2, 2079)
    AddPerft(POS6, 3, 89890)

    '' Special cases: illegal en passant, castling, promotion, stalemate.
    AddPerft("3k4/3p4/8/K1P4r/8/8/8/8 b - - 0 1", 6, 1134888)
    AddPerft("8/8/4k3/8/2p5/8/B2P2K1/8 w - - 0 1", 6, 1015133)
    AddPerft("8/8/1k6/2b5/2pP4/8/5K2/8 b - d3 0 1", 6, 1440467)
    AddPerft("5k2/8/8/8/8/8/8/4K2R w K - 0 1", 6, 661072)
    AddPerft("3k4/8/8/8/8/8/8/R3K3 w Q - 0 1", 6, 803711)
    AddPerft("r3k2r/1b4bq/8/8/8/8/7B/R3K2R w KQkq - 0 1", 4, 1274206)
    AddPerft("r3k2r/8/3Q4/8/8/5q2/8/R3K2R b KQkq - 0 1", 4, 1720476)
    AddPerft("2K2r2/4P3/8/8/8/8/8/3k4 w - - 0 1", 6, 3821001)
    AddPerft("8/8/1P2K3/8/2n5/1q6/8/5k2 b - - 0 1", 5, 1004658)
    AddPerft("4k3/1P6/8/8/8/8/K7/8 w - - 0 1", 6, 217342)
    AddPerft("8/P1k5/K7/8/8/8/8/8 w - - 0 1", 6, 92683)
    AddPerft("K1k5/8/P7/8/8/8/8/8 w - - 0 1", 6, 2217)
    AddPerft("8/k1P5/8/1K6/8/8/8/8 w - - 0 1", 7, 567584)
    AddPerft("8/8/2k5/5q2/5n2/8/5K2/8 b - - 0 1", 4, 23527)

    If full Then
        AddPerft(START_FEN, 5, 4865609)
        AddPerft(KIWI, 4, 4085603)
        AddPerft(POS3, 6, 11030083)
        AddPerft(POS4, 4, 422333)
        AddPerft(POS4M, 4, 422333)
        AddPerft(POS5, 4, 2103487)
        AddPerft(POS6, 4, 3894594)
    End If
End Sub

Sub RunPerftSuite(ByVal full As Boolean)
    Print "Perft suite" & IIf(full, " (full)", " (quick)") & "..."
    BuildPerftSuite(full)
    Static p As Position
    Dim As String errMsg
    Dim As ULongInt totalNodes = 0
    Dim As Double t0 = Timer
    Dim As Integer i
    For i = 0 To PerftCount - 1
        With PerftCases(i)
            If Not Pos_LoadFEN(p, .fen, errMsg) Then
                Check False, "perft FEN load: " & .fen, errMsg
                Continue For
            End If
            Dim As ULongInt n = Pos_Perft(p, .depth)
            totalNodes += n
            Check n = .nodes, "perft(" & .depth & ") " & .fen, "got " & n & ", expected " & .nodes
            Check p.historyCount = 0, "perft leaves the undo stack empty"
        End With
    Next
    Dim As Double secs = Timer - t0
    If secs < 0.001 Then secs = 0.001
    Print Using "  ###,###,### nodes in ###.## s  (##,###,### nodes/s)"; totalNodes; secs; totalNodes / secs
End Sub

Sub Divide(ByRef fen As Const String, ByVal depth As Integer)
    Static p As Position
    Dim As String errMsg
    If Not Pos_LoadFEN(p, fen, errMsg) Then
        Print "Bad FEN: " & errMsg
        Exit Sub
    End If
    Dim As MoveList list
    Pos_GenerateLegal(p, list)
    Dim As ULongInt total = 0
    Dim As Integer i
    For i = 0 To list.count - 1
        Pos_MakeMove(p, list.moves(i))
        Dim As ULongInt n = Pos_Perft(p, depth - 1)
        Pos_UnmakeMove(p)
        Print Notation_MoveToUCI(list.moves(i)) & ": " & n
        total += n
    Next
    Print "Moves: " & list.count & "   Total: " & total
End Sub

'' ---------------------------------------------------------------------
'' Main
'' ---------------------------------------------------------------------
Dim As String arg1 = Command(1)
If arg1 = "--perft" OrElse arg1 = "--divide" Then
    Dim As String fen = Command(2)
    Dim As Integer depth = ValInt(Command(3))
    If fen = "" OrElse depth < 1 Then
        Print "Usage: test_core " & arg1 & " ""<fen>"" <depth>"
        End 2
    End If
    If arg1 = "--divide" Then
        Divide(fen, depth)
    Else
        Static p As Position
        Dim As String errMsg
        If Not Pos_LoadFEN(p, fen, errMsg) Then Print "Bad FEN: " & errMsg : End 2
        Dim As Double t0 = Timer
        Dim As ULongInt n = Pos_Perft(p, depth)
        Print Using "perft(#) = &  (###.## s)"; depth; Str(n); Timer - t0
    End If
    End 0
End If

Print "BeginnerChess core tests (version " & CM_VERSION & ")"
TestFEN()
TestMakeUnmakeAndHash()
TestRulesPositions()
TestGameEnd()
TestSAN()
RunPerftSuite(arg1 = "--full")
Print
Print "Passed: " & TestsPassed & "   Failed: " & TestsFailed
If TestsFailed > 0 Then End 1
End 0
