'' =====================================================================
'' BeginnerChess - engine.bas
'' The computer chess player. See engine.bi for an overview.
'' =====================================================================
#include once "engine.bi"

'' =====================================================================
'' Levels and styles
'' =====================================================================
Function Engine_LevelName(ByVal level As Integer) As String
    Select Case level
    Case LEVEL_BEGINNER     : Return "Beginner"
    Case LEVEL_EASY         : Return "Easy"
    Case LEVEL_NORMAL       : Return "Normal"
    Case LEVEL_INTERMEDIATE : Return "Intermediate"
    Case LEVEL_ADVANCED     : Return "Advanced"
    End Select
    Return "?"
End Function

Function Engine_StyleName(ByVal style As Integer) As String
    Select Case style
    Case STYLE_BALANCED   : Return "Balanced"
    Case STYLE_DEFENSIVE  : Return "Defensive"
    Case STYLE_AGGRESSIVE : Return "Aggressive"
    Case STYLE_POSITIONAL : Return "Positional"
    Case STYLE_TACTICAL   : Return "Tactical"
    Case STYLE_MATERIAL   : Return "Material"
    End Select
    Return "?"
End Function

Function Engine_LevelDescription(ByVal level As Integer) As String
    Select Case level
    Case LEVEL_BEGINNER
        Return "Just learning: looks only one move ahead and often overlooks your threats."
    Case LEVEL_EASY
        Return "Sees simple captures and threats, but not much more."
    Case LEVEL_NORMAL
        Return "A fair opponent for a casual player."
    Case LEVEL_INTERMEDIATE
        Return "Thinks several moves ahead and punishes mistakes."
    Case LEVEL_ADVANCED
        Return "The strongest setting of the computer. Good luck!"
    End Select
    Return ""
End Function

Function Engine_StyleDescription(ByVal style As Integer) As String
    Select Case style
    Case STYLE_BALANCED   : Return "Plays solid, all-round chess."
    Case STYLE_DEFENSIVE  : Return "Keeps its king safe and its pawns healthy; happy with a draw."
    Case STYLE_AGGRESSIVE : Return "Goes after your king and avoids draws."
    Case STYLE_POSITIONAL : Return "Likes space, good pawn structure and active rooks."
    Case STYLE_TACTICAL   : Return "Looks for threats, forks and active pieces."
    Case STYLE_MATERIAL   : Return "Counts pieces: grabs material and hates losing any."
    End Select
    Return ""
End Function

Sub Engine_LevelParams(ByVal level As Integer, ByVal style As Integer, ByRef prm As EngineParams)
    prm.style = style
    prm.contempt = 0
    Select Case level
    Case LEVEL_BEGINNER
        prm.maxDepth = 1 : prm.timeLimitMs = 500 : prm.useQuiescence = False
        prm.noise = 60 : prm.temperature = 90 : prm.margin = 250 : prm.blunderChance = 0.10
        prm.minThinkMs = 700
    Case LEVEL_EASY
        prm.maxDepth = 2 : prm.timeLimitMs = 700 : prm.useQuiescence = True
        prm.noise = 35 : prm.temperature = 45 : prm.margin = 150 : prm.blunderChance = 0.05
        prm.minThinkMs = 700
    Case LEVEL_NORMAL
        prm.maxDepth = 4 : prm.timeLimitMs = 1000 : prm.useQuiescence = True
        prm.noise = 12 : prm.temperature = 15 : prm.margin = 60 : prm.blunderChance = 0
        prm.minThinkMs = 500
    Case LEVEL_INTERMEDIATE
        prm.maxDepth = 7 : prm.timeLimitMs = 2500 : prm.useQuiescence = True
        prm.noise = 0 : prm.temperature = 0 : prm.margin = 0 : prm.blunderChance = 0
        prm.minThinkMs = 300
    Case Else
        prm.maxDepth = MAX_SEARCH_PLY - 4 : prm.timeLimitMs = 5000 : prm.useQuiescence = True
        prm.noise = 0 : prm.temperature = 0 : prm.margin = 0 : prm.blunderChance = 0
        prm.minThinkMs = 200
    End Select
    '' Beginners know only the first few opening moves.
    Dim As Integer bookByLevel(0 To 4) = {4, 6, 10, 16, 24}
    prm.bookPlies = bookByLevel(IIf(level >= 0 AndAlso level <= 4, level, 4))
    Select Case style
    Case STYLE_AGGRESSIVE : prm.contempt = 30
    Case STYLE_TACTICAL   : prm.contempt = 15
    Case STYLE_DEFENSIVE  : prm.contempt = -10
    End Select
End Sub

'' =====================================================================
'' Random numbers (own generator: thread-safe and reproducible)
'' =====================================================================
Dim Shared EngRng As ULongInt = &h2545F4914F6CDD1Dull

Private Function RandU() As ULongInt
    EngRng Xor= (EngRng Shl 13)
    EngRng Xor= (EngRng Shr 7)
    EngRng Xor= (EngRng Shl 17)
    Return EngRng
End Function

Private Function RandFloat() As Double       '' 0 <= x < 1
    Return (RandU() Shr 11) / 9007199254740992.0
End Function

Private Function RandRange(ByVal lo As Integer, ByVal hi As Integer) As Integer
    If hi <= lo Then Return lo
    Return lo + CInt(RandU() Mod CULngInt(hi - lo + 1))
End Function

'' =====================================================================
'' Evaluation
'' =====================================================================
'' Piece-square tables, written as seen from White (first row = rank 8).
'' Values follow well-known teaching principles: knights and bishops
'' belong in the centre, pawns should advance in the centre, the king
'' hides in the middlegame and becomes active in the endgame.
Dim Shared PstPawnMg(0 To 63) As Integer = { _
      0,  0,  0,  0,  0,  0,  0,  0, _
     50, 50, 50, 50, 50, 50, 50, 50, _
     10, 10, 20, 30, 30, 20, 10, 10, _
      5,  5, 10, 25, 25, 10,  5,  5, _
      0,  0,  0, 20, 20,  0,  0,  0, _
      5, -5,-10,  0,  0,-10, -5,  5, _
      5, 10, 10,-20,-20, 10, 10,  5, _
      0,  0,  0,  0,  0,  0,  0,  0 }
Dim Shared PstPawnEg(0 To 63) As Integer = { _
      0,  0,  0,  0,  0,  0,  0,  0, _
     70, 70, 70, 70, 70, 70, 70, 70, _
     40, 40, 40, 40, 40, 40, 40, 40, _
     20, 20, 20, 20, 20, 20, 20, 20, _
     10, 10, 10, 10, 10, 10, 10, 10, _
      5,  5,  5,  5,  5,  5,  5,  5, _
      0,  0,  0,  0,  0,  0,  0,  0, _
      0,  0,  0,  0,  0,  0,  0,  0 }
Dim Shared PstKnight(0 To 63) As Integer = { _
    -50,-40,-30,-30,-30,-30,-40,-50, _
    -40,-20,  0,  0,  0,  0,-20,-40, _
    -30,  0, 10, 15, 15, 10,  0,-30, _
    -30,  5, 15, 20, 20, 15,  5,-30, _
    -30,  0, 15, 20, 20, 15,  0,-30, _
    -30,  5, 10, 15, 15, 10,  5,-30, _
    -40,-20,  0,  5,  5,  0,-20,-40, _
    -50,-40,-30,-30,-30,-30,-40,-50 }
Dim Shared PstBishop(0 To 63) As Integer = { _
    -20,-10,-10,-10,-10,-10,-10,-20, _
    -10,  0,  0,  0,  0,  0,  0,-10, _
    -10,  0,  5, 10, 10,  5,  0,-10, _
    -10,  5,  5, 10, 10,  5,  5,-10, _
    -10,  0, 10, 10, 10, 10,  0,-10, _
    -10, 10, 10, 10, 10, 10, 10,-10, _
    -10,  5,  0,  0,  0,  0,  5,-10, _
    -20,-10,-10,-10,-10,-10,-10,-20 }
Dim Shared PstRook(0 To 63) As Integer = { _
      0,  0,  0,  0,  0,  0,  0,  0, _
      5, 10, 10, 10, 10, 10, 10,  5, _
     -5,  0,  0,  0,  0,  0,  0, -5, _
     -5,  0,  0,  0,  0,  0,  0, -5, _
     -5,  0,  0,  0,  0,  0,  0, -5, _
     -5,  0,  0,  0,  0,  0,  0, -5, _
     -5,  0,  0,  0,  0,  0,  0, -5, _
      0,  0,  0,  5,  5,  0,  0,  0 }
Dim Shared PstQueen(0 To 63) As Integer = { _
    -20,-10,-10, -5, -5,-10,-10,-20, _
    -10,  0,  0,  0,  0,  0,  0,-10, _
    -10,  0,  5,  5,  5,  5,  0,-10, _
     -5,  0,  5,  5,  5,  5,  0, -5, _
      0,  0,  5,  5,  5,  5,  0, -5, _
    -10,  5,  5,  5,  5,  5,  0,-10, _
    -10,  0,  5,  0,  0,  0,  0,-10, _
    -20,-10,-10, -5, -5,-10,-10,-20 }
Dim Shared PstKingMg(0 To 63) As Integer = { _
    -30,-40,-40,-50,-50,-40,-40,-30, _
    -30,-40,-40,-50,-50,-40,-40,-30, _
    -30,-40,-40,-50,-50,-40,-40,-30, _
    -30,-40,-40,-50,-50,-40,-40,-30, _
    -20,-30,-30,-40,-40,-30,-30,-20, _
    -10,-20,-20,-20,-20,-20,-20,-10, _
     20, 20,  0,  0,  0,  0, 20, 20, _
     20, 30, 10,  0,  0, 10, 30, 20 }
Dim Shared PstKingEg(0 To 63) As Integer = { _
    -50,-40,-30,-20,-20,-30,-40,-50, _
    -30,-20,-10,  0,  0,-10,-20,-30, _
    -30,-10, 20, 30, 30, 20,-10,-30, _
    -30,-10, 30, 40, 40, 30,-10,-30, _
    -30,-10, 30, 40, 40, 30,-10,-30, _
    -30,-10, 20, 30, 30, 20,-10,-30, _
    -30,-30,  0,  0,  0,  0,-30,-30, _
    -50,-30,-30,-30,-30,-30,-30,-50 }

Dim Shared PieceValMg(0 To 6) As Integer = {0, 100, 320, 330, 500, 950, 0}
Dim Shared PieceValEg(0 To 6) As Integer = {0, 120, 300, 320, 540, 1000, 0}
'' Simple values for move ordering, threats and delta pruning.
Dim Shared PieceVal(0 To 6) As Integer = {0, 100, 320, 330, 500, 950, 20000}
Dim Shared PhaseWeight(0 To 6) As Integer = {0, 0, 1, 1, 2, 4, 0}

Dim Shared PassedMg(0 To 7) As Integer = {0, 5, 10, 15, 25, 40, 60, 0}
Dim Shared PassedEg(0 To 7) As Integer = {0, 10, 18, 30, 50, 80, 120, 0}

Dim Shared EvKnightOff(0 To 7) As Integer = {33, 31, 18, 14, -33, -31, -18, -14}
Dim Shared EvKingOff(0 To 7) As Integer = {1, -1, 16, -16, 15, 17, -15, -17}
Dim Shared EvDiag(0 To 3) As Integer = {15, 17, -15, -17}
Dim Shared EvOrtho(0 To 3) As Integer = {1, -1, 16, -16}

'' Style weights: own(term) applies to the engine's side, opp(term) to
'' the opponent's side.
Type StyleWeights
    own(0 To EVAL_TERM_COUNT - 1) As Single
    opp(0 To EVAL_TERM_COUNT - 1) As Single
End Type
Dim Shared Styles(0 To STYLE_COUNT - 1) As StyleWeights
Dim Shared StylesReady As Boolean = False

Private Sub InitStyles()
    If StylesReady Then Exit Sub
    Dim As Integer s, t
    For s = 0 To STYLE_COUNT - 1
        For t = 0 To EVAL_TERM_COUNT - 1
            Styles(s).own(t) = 1
            Styles(s).opp(t) = 1
        Next
    Next
    With Styles(STYLE_DEFENSIVE)
        .own(EV_KING_SAFETY) = 1.7 : .opp(EV_KING_SAFETY) = 0.9
        .own(EV_PAWN_STRUCTURE) = 1.3 : .opp(EV_PAWN_STRUCTURE) = 1.3
        .own(EV_THREATS) = 1.4 : .opp(EV_THREATS) = 0.8
        .own(EV_MOBILITY) = 0.8
    End With
    With Styles(STYLE_AGGRESSIVE)
        .opp(EV_KING_SAFETY) = 1.8 : .own(EV_KING_SAFETY) = 0.7
        .own(EV_MOBILITY) = 1.3
        .opp(EV_THREATS) = 1.3 : .own(EV_THREATS) = 0.9
        .own(EV_DEVELOPMENT) = 1.3
    End With
    With Styles(STYLE_POSITIONAL)
        .own(EV_PAWN_STRUCTURE) = 1.5 : .opp(EV_PAWN_STRUCTURE) = 1.5
        .own(EV_SPACE) = 2.0 : .opp(EV_SPACE) = 1.5
        .own(EV_ROOKS) = 1.4 : .own(EV_BISHOP_PAIR) = 1.4
        .own(EV_CENTER) = 1.5 : .own(EV_MOBILITY) = 1.2
        .own(EV_THREATS) = 0.8 : .opp(EV_THREATS) = 0.8
    End With
    With Styles(STYLE_TACTICAL)
        .own(EV_THREATS) = 1.7 : .opp(EV_THREATS) = 1.7
        .own(EV_MOBILITY) = 1.3 : .opp(EV_MOBILITY) = 1.1
        .opp(EV_KING_SAFETY) = 1.3
    End With
    With Styles(STYLE_MATERIAL)
        For t = 0 To EVAL_TERM_COUNT - 1
            If t <> EV_MATERIAL AndAlso t <> EV_ENDGAME Then .own(t) = 0.7 : .opp(t) = 0.7
        Next
        .own(EV_THREATS) = 1.3 : .opp(EV_THREATS) = 1.1
    End With
    StylesReady = True
End Sub

#define SQ64(s)  (SQ_RANK(s) * 8 + SQ_FILE(s))
#define PSTIDX(side, s)  (IIf((side) = SIDE_WHITE, (7 - SQ_RANK(s)) * 8 + SQ_FILE(s), SQ_RANK(s) * 8 + SQ_FILE(s)))

Private Function KingDistance(ByVal a As Integer, ByVal b As Integer) As Integer
    Dim As Integer df = Abs(SQ_FILE(a) - SQ_FILE(b)), dr = Abs(SQ_RANK(a) - SQ_RANK(b))
    Return IIf(df > dr, df, dr)
End Function

Private Function CenterDistance(ByVal s As Integer) As Integer
    Dim As Integer f = SQ_FILE(s), r = SQ_RANK(s)
    Dim As Integer df = IIf(f < 4, 3 - f, f - 4), dr = IIf(r < 4, 3 - r, r - 4)
    Return df + dr
End Function

'' Computes the evaluation terms. mgT/egT(side, term) are bonuses for
'' 'side' (negative = penalty). Returns the game phase (24 = opening,
'' 0 = bare kings).
Private Function ComputeTerms(ByRef p As Position, mgT() As Integer, egT() As Integer) As Integer
    Dim As Integer s, side, enemy, pc, pt, i, t, d
    Dim As Integer pawnCount(0 To 1, 0 To 7)
    Dim As Integer pawnRanks(0 To 1, 0 To 7)            '' bit r set = pawn on rank r
    Dim As UByte att(0 To 1, 0 To 127)
    Dim As UByte pawnAtt(0 To 1, 0 To 127)
    Dim As Integer bishops(0 To 1), queens(0 To 1), nonPawnMat(0 To 1), totalMat(0 To 1), pawnsTotal(0 To 1)
    Dim As Integer phase = 0

    '' --- Pass 1: material, piece-square tables, pawn maps -------------
    For s = 0 To 119
        If SQ_OFFBOARD(s) Then Continue For
        pc = p.board(s)
        If pc = PC_EMPTY Then Continue For
        side = PIECE_COLOR(pc) : pt = PIECE_TYPE(pc)
        Dim As Integer idx = PSTIDX(side, s)
        mgT(side, EV_MATERIAL) += PieceValMg(pt)
        egT(side, EV_MATERIAL) += PieceValEg(pt)
        totalMat(side) += PieceVal(pt) * IIf(pt = PT_KING, 0, 1)
        phase += PhaseWeight(pt)
        Select Case pt
        Case PT_PAWN
            mgT(side, EV_PIECE_SQUARES) += PstPawnMg(idx)
            egT(side, EV_PIECE_SQUARES) += PstPawnEg(idx)
            pawnCount(side, SQ_FILE(s)) += 1
            pawnRanks(side, SQ_FILE(s)) Or= (1 Shl SQ_RANK(s))
            pawnsTotal(side) += 1
            Dim As Integer fwd = IIf(side = SIDE_WHITE, 16, -16)
            t = s + fwd - 1 : If Not SQ_OFFBOARD(t) Then pawnAtt(side, t) = 1 : att(side, t) += 1
            t = s + fwd + 1 : If Not SQ_OFFBOARD(t) Then pawnAtt(side, t) = 1 : att(side, t) += 1
        Case PT_KNIGHT
            mgT(side, EV_PIECE_SQUARES) += PstKnight(idx)
            egT(side, EV_PIECE_SQUARES) += PstKnight(idx)
            nonPawnMat(side) += PieceVal(pt)
        Case PT_BISHOP
            mgT(side, EV_PIECE_SQUARES) += PstBishop(idx)
            egT(side, EV_PIECE_SQUARES) += PstBishop(idx)
            nonPawnMat(side) += PieceVal(pt)
            bishops(side) += 1
        Case PT_ROOK
            mgT(side, EV_PIECE_SQUARES) += PstRook(idx)
            egT(side, EV_PIECE_SQUARES) += PstRook(idx)
            nonPawnMat(side) += PieceVal(pt)
        Case PT_QUEEN
            mgT(side, EV_PIECE_SQUARES) += PstQueen(idx)
            egT(side, EV_PIECE_SQUARES) += PstQueen(idx)
            nonPawnMat(side) += PieceVal(pt)
            queens(side) += 1
        Case PT_KING
            mgT(side, EV_PIECE_SQUARES) += PstKingMg(idx)
            egT(side, EV_PIECE_SQUARES) += PstKingEg(idx)
        End Select
    Next
    If phase > 24 Then phase = 24

    '' --- Pass 2: attacks, mobility, rooks -----------------------------
    For s = 0 To 119
        If SQ_OFFBOARD(s) Then Continue For
        pc = p.board(s)
        If pc = PC_EMPTY Then Continue For
        side = PIECE_COLOR(pc) : pt = PIECE_TYPE(pc) : enemy = side Xor 1
        If pt = PT_PAWN Then Continue For
        Dim As Integer mob = 0
        Select Case pt
        Case PT_KNIGHT
            For i = 0 To 7
                t = s + EvKnightOff(i)
                If SQ_OFFBOARD(t) Then Continue For
                att(side, t) += 1
                If (p.board(t) = PC_EMPTY OrElse PIECE_COLOR(p.board(t)) = enemy) AndAlso pawnAtt(enemy, t) = 0 Then mob += 1
            Next
            mgT(side, EV_MOBILITY) += (mob - 4) * 4
            egT(side, EV_MOBILITY) += (mob - 4) * 4
        Case PT_KING
            For i = 0 To 7
                t = s + EvKingOff(i)
                If Not SQ_OFFBOARD(t) Then att(side, t) += 1
            Next
        Case Else
            Dim As Integer dirsFrom = IIf(pt = PT_ROOK, 4, 0), dirsTo = IIf(pt = PT_BISHOP, 3, 7)
            For i = dirsFrom To dirsTo
                d = IIf(i < 4, EvDiag(i And 3), EvOrtho(i And 3))
                t = s + d
                Do While Not SQ_OFFBOARD(t)
                    att(side, t) += 1
                    If p.board(t) = PC_EMPTY Then
                        If pawnAtt(enemy, t) = 0 Then mob += 1
                    Else
                        If PIECE_COLOR(p.board(t)) = enemy Then mob += 1
                        Exit Do
                    End If
                    t += d
                Loop
            Next
            Select Case pt
            Case PT_BISHOP
                mgT(side, EV_MOBILITY) += (mob - 6) * 5
                egT(side, EV_MOBILITY) += (mob - 6) * 5
            Case PT_ROOK
                mgT(side, EV_MOBILITY) += (mob - 7) * 2
                egT(side, EV_MOBILITY) += (mob - 7) * 4
                '' Rook files
                Dim As Integer f = SQ_FILE(s)
                If pawnCount(side, f) = 0 Then
                    If pawnCount(enemy, f) = 0 Then
                        mgT(side, EV_ROOKS) += 22 : egT(side, EV_ROOKS) += 10
                    Else
                        mgT(side, EV_ROOKS) += 11 : egT(side, EV_ROOKS) += 6
                    End If
                End If
                '' Rook on the 7th rank
                Dim As Integer seventh = IIf(side = SIDE_WHITE, 6, 1), eighth = IIf(side = SIDE_WHITE, 7, 0)
                If SQ_RANK(s) = seventh Then
                    Dim As Integer enemyPawnsOn7 = 0
                    For i = 0 To 7
                        If (pawnRanks(enemy, i) And (1 Shl seventh)) <> 0 Then enemyPawnsOn7 = 1
                    Next
                    If SQ_RANK(p.kingSq(enemy)) = eighth OrElse enemyPawnsOn7 Then
                        mgT(side, EV_ROOKS) += 20 : egT(side, EV_ROOKS) += 30
                    End If
                End If
            Case PT_QUEEN
                mgT(side, EV_MOBILITY) += (mob - 13) * 1
                egT(side, EV_MOBILITY) += (mob - 13) * 2
            End Select
        End Select
    Next

    '' --- Per side terms ----------------------------------------------
    For side = SIDE_WHITE To SIDE_BLACK
        enemy = side Xor 1
        Dim As Integer homeRank = IIf(side = SIDE_WHITE, 0, 7)
        Dim As Integer fwd = IIf(side = SIDE_WHITE, 1, -1)
        Dim As Integer ownKing = p.kingSq(side), enemyKing = p.kingSq(enemy)

        '' Development (middlegame): minor pieces still at home, early queen.
        Dim As Integer undeveloped = 0
        Dim As Integer nOwn = MAKE_PIECE(side, PT_KNIGHT), bOwn = MAKE_PIECE(side, PT_BISHOP)
        If p.board(MAKE_SQ(1, homeRank)) = nOwn Then undeveloped += 1
        If p.board(MAKE_SQ(6, homeRank)) = nOwn Then undeveloped += 1
        If p.board(MAKE_SQ(2, homeRank)) = bOwn Then undeveloped += 1
        If p.board(MAKE_SQ(5, homeRank)) = bOwn Then undeveloped += 1
        mgT(side, EV_DEVELOPMENT) -= undeveloped * 12
        If queens(side) > 0 AndAlso p.board(MAKE_SQ(3, homeRank)) <> MAKE_PIECE(side, PT_QUEEN) AndAlso undeveloped >= 2 Then
            mgT(side, EV_DEVELOPMENT) -= 18
        End If
        Dim As Integer rightsMask = IIf(side = SIDE_WHITE, CR_WHITE_KING Or CR_WHITE_QUEEN, CR_BLACK_KING Or CR_BLACK_QUEEN)
        If (p.castling And rightsMask) = 0 AndAlso SQ_RANK(ownKing) = homeRank AndAlso _
           (SQ_FILE(ownKing) = 3 OrElse SQ_FILE(ownKing) = 4) Then
            mgT(side, EV_DEVELOPMENT) -= 25                 '' lost the right to castle
        End If

        '' Pawn structure and passed pawns.
        Dim As Integer f, r
        For f = 0 To 7
            If pawnCount(side, f) > 1 Then
                mgT(side, EV_PAWN_STRUCTURE) -= (pawnCount(side, f) - 1) * 10
                egT(side, EV_PAWN_STRUCTURE) -= (pawnCount(side, f) - 1) * 20
            End If
            If pawnCount(side, f) = 0 Then Continue For
            Dim As Integer leftCnt = IIf(f > 0, pawnCount(side, f - 1), 0)
            Dim As Integer rightCnt = IIf(f < 7, pawnCount(side, f + 1), 0)
            If leftCnt = 0 AndAlso rightCnt = 0 Then
                mgT(side, EV_PAWN_STRUCTURE) -= 12 * pawnCount(side, f)
                egT(side, EV_PAWN_STRUCTURE) -= 16 * pawnCount(side, f)
            End If
            For r = 1 To 6
                If (pawnRanks(side, f) And (1 Shl r)) = 0 Then Continue For
                Dim As Integer aheadMask
                If side = SIDE_WHITE Then
                    aheadMask = (&hFF Shl (r + 1)) And &hFF
                Else
                    aheadMask = (1 Shl r) - 1
                End If
                Dim As Integer blockers = pawnRanks(enemy, f)
                If f > 0 Then blockers Or= pawnRanks(enemy, f - 1)
                If f < 7 Then blockers Or= pawnRanks(enemy, f + 1)
                If (blockers And aheadMask) <> 0 Then Continue For
                '' Passed pawn!
                Dim As Integer rr = IIf(side = SIDE_WHITE, r, 7 - r)
                Dim As Integer psq = MAKE_SQ(f, r)
                mgT(side, EV_PASSED_PAWNS) += PassedMg(rr)
                egT(side, EV_PASSED_PAWNS) += PassedEg(rr)
                Dim As Integer front = psq + fwd * 16
                If p.board(front) = PC_EMPTY Then egT(side, EV_PASSED_PAWNS) += rr * 3
                Dim As Integer distOwn = KingDistance(ownKing, front), distEnemy = KingDistance(enemyKing, front)
                egT(side, EV_PASSED_PAWNS) += (distEnemy * 5 - distOwn * 2) * rr \ 2
                '' Rule of the square: unstoppable in a pure pawn ending.
                If nonPawnMat(enemy) = 0 Then
                    Dim As Integer promoSq = MAKE_SQ(f, IIf(side = SIDE_WHITE, 7, 0))
                    Dim As Integer pawnDist = 7 - rr
                    If rr = 1 Then pawnDist = 5
                    Dim As Integer kd = KingDistance(enemyKing, promoSq)
                    If p.sideToMove = enemy Then kd -= 1
                    If kd > pawnDist Then egT(side, EV_PASSED_PAWNS) += 400
                End If
            Next
        Next

        '' King safety (middlegame only).
        Dim As Integer kf = SQ_FILE(ownKing), kr = SQ_RANK(ownKing)
        Dim As Integer ks = 0
        If kr = homeRank OrElse kr = homeRank + fwd Then
            If kf <= 2 OrElse kf >= 5 Then
                For f = IIf(kf > 0, kf - 1, 0) To IIf(kf < 7, kf + 1, 7)
                    Dim As Integer r1 = kr + fwd, r2 = kr + 2 * fwd
                    If r1 >= 0 AndAlso r1 <= 7 AndAlso (pawnRanks(side, f) And (1 Shl r1)) <> 0 Then
                        ks += 12
                    ElseIf r2 >= 0 AndAlso r2 <= 7 AndAlso (pawnRanks(side, f) And (1 Shl r2)) <> 0 Then
                        ks += 6
                    Else
                        ks -= 14
                    End If
                    If pawnCount(side, f) = 0 Then ks -= 10
                    If pawnCount(side, f) = 0 AndAlso pawnCount(enemy, f) = 0 Then ks -= 10
                Next
            Else
                '' King still in the centre: open central files are dangerous.
                For f = 3 To 4
                    If pawnCount(side, f) = 0 Then ks -= 15
                Next
            End If
        End If
        '' Enemy pressure on the squares around the king.
        Dim As Integer units = 0, zs
        For i = 0 To 7
            zs = ownKing + EvKingOff(i)
            If SQ_OFFBOARD(zs) Then Continue For
            units += att(enemy, zs)
            If att(enemy, zs) > 0 AndAlso att(side, zs) <= 1 Then units += 1
        Next
        For i = -1 To 1
            zs = ownKing + fwd * 32 + i
            If Not SQ_OFFBOARD(zs) Then units += att(enemy, zs)
        Next
        Dim As Integer danger = units * units * 2
        If danger > 450 Then danger = 450
        If queens(enemy) = 0 Then danger = danger * 2 \ 5
        ks -= danger
        mgT(side, EV_KING_SAFETY) += ks

        '' Bishop pair.
        If bishops(side) >= 2 Then
            mgT(side, EV_BISHOP_PAIR) += 30 : egT(side, EV_BISHOP_PAIR) += 50
        End If

        '' Centre control.
        Dim As Integer centerSq(0 To 3) = {MAKE_SQ(3, 3), MAKE_SQ(4, 3), MAKE_SQ(3, 4), MAKE_SQ(4, 4)}
        Dim As Integer cc = 0
        For i = 0 To 3
            cc += att(side, centerSq(i))
        Next
        If cc > 10 Then cc = 10
        mgT(side, EV_CENTER) += cc * 4

        '' Space: safe squares on our side of the centre files.
        Dim As Integer spaceCnt = 0
        For f = 2 To 5
            For r = IIf(side = SIDE_WHITE, 1, 4) To IIf(side = SIDE_WHITE, 3, 6)
                zs = MAKE_SQ(f, r)
                If pawnAtt(enemy, zs) = 0 AndAlso att(side, zs) > 0 Then spaceCnt += 1
            Next
        Next
        mgT(side, EV_SPACE) += spaceCnt * 2

        '' Threats against this side's pieces.
        Dim As Integer threatMg = 0, threatEg = 0
        For s = 0 To 119
            If SQ_OFFBOARD(s) Then Continue For
            pc = p.board(s)
            If pc = PC_EMPTY OrElse PIECE_COLOR(pc) <> side Then Continue For
            pt = PIECE_TYPE(pc)
            If pt = PT_KING Then Continue For
            Dim As Integer v = PieceVal(pt)
            If pt <> PT_PAWN AndAlso pawnAtt(enemy, s) <> 0 Then
                threatMg += v \ 8 + 10 : threatEg += v \ 10 + 8
            ElseIf att(enemy, s) > 0 AndAlso att(side, s) = 0 Then
                threatMg += v \ 10 + 10 : threatEg += v \ 10 + 10
            End If
        Next
        If p.sideToMove = side Then
            threatMg \= 2 : threatEg \= 2
        End If
        mgT(side, EV_THREATS) -= threatMg
        egT(side, EV_THREATS) -= threatEg
    Next

    '' --- Endgame: drive a bare king to the edge ("mop-up") -----------
    For side = SIDE_WHITE To SIDE_BLACK
        enemy = side Xor 1
        If pawnsTotal(enemy) = 0 AndAlso totalMat(side) - totalMat(enemy) >= 400 AndAlso phase <= 12 Then
            Dim As Integer bonus = CenterDistance(p.kingSq(enemy)) * 10
            Dim As Integer kd = Abs(SQ_FILE(p.kingSq(side)) - SQ_FILE(p.kingSq(enemy))) + _
                                Abs(SQ_RANK(p.kingSq(side)) - SQ_RANK(p.kingSq(enemy)))
            bonus += (14 - kd) * 4
            mgT(side, EV_ENDGAME) += bonus
            egT(side, EV_ENDGAME) += bonus
        End If
    Next
    Return phase
End Function

'' Material-based draw scaling: returns a factor out of 16.
Private Function DrawScale(ByRef p As Position, ByVal whiteAhead As Boolean) As Integer
    Dim As Integer s, pawns(0 To 1), minors(0 To 1), majors(0 To 1), npm(0 To 1)
    For s = 0 To 119
        If SQ_OFFBOARD(s) Then Continue For
        Dim As Integer pc = p.board(s)
        If pc = PC_EMPTY Then Continue For
        Dim As Integer side = PIECE_COLOR(pc)
        Select Case PIECE_TYPE(pc)
        Case PT_PAWN : pawns(side) += 1
        Case PT_KNIGHT, PT_BISHOP : minors(side) += 1 : npm(side) += 320
        Case PT_ROOK : majors(side) += 1 : npm(side) += 500
        Case PT_QUEEN : majors(side) += 1 : npm(side) += 950
        End Select
    Next
    Dim As Integer strong = IIf(whiteAhead, SIDE_WHITE, SIDE_BLACK), weak = strong Xor 1
    If pawns(strong) = 0 Then
        If npm(strong) - npm(weak) < 400 Then Return 2      '' e.g. KR v KB, KNN v K
    End If
    Return 16
End Function

Private Function EvaluateWhite(ByRef p As Position, ByVal style As Integer, ByVal engineSide As Integer) As Integer
    InitStyles()
    Dim As Integer mgT(0 To 1, 0 To EVAL_TERM_COUNT - 1), egT(0 To 1, 0 To EVAL_TERM_COUNT - 1)
    Dim As Integer phase = ComputeTerms(p, mgT(), egT())
    Dim As Single total = 0
    Dim As Integer side, t
    If style < 0 OrElse style >= STYLE_COUNT Then style = STYLE_BALANCED
    For side = SIDE_WHITE To SIDE_BLACK
        Dim As Single sign = IIf(side = SIDE_WHITE, 1, -1)
        For t = 0 To EVAL_TERM_COUNT - 1
            Dim As Single v = (mgT(side, t) * phase + egT(side, t) * (24 - phase)) / 24
            Dim As Single w = 1
            If engineSide >= 0 Then
                If side = engineSide Then w = Styles(style).own(t) Else w = Styles(style).opp(t)
            End If
            total += sign * w * v
        Next
    Next
    '' Tempo: the side to move has a small advantage.
    total += IIf(p.sideToMove = SIDE_WHITE, 10, -10) * phase / 24
    Dim As Integer score = CInt(total)
    If score <> 0 Then score = score * DrawScale(p, score > 0) \ 16
    Return score
End Function

Function Engine_Evaluate(ByRef p As Position, ByVal style As Integer = STYLE_BALANCED, _
                         ByVal engineSide As Integer = -1) As Integer
    Dim As Integer w = EvaluateWhite(p, style, engineSide)
    Return IIf(p.sideToMove = SIDE_WHITE, w, -w)
End Function

Sub Engine_EvaluateTerms(ByRef p As Position, terms() As Integer)
    Dim As Integer mgT(0 To 1, 0 To EVAL_TERM_COUNT - 1), egT(0 To 1, 0 To EVAL_TERM_COUNT - 1)
    Dim As Integer phase = ComputeTerms(p, mgT(), egT()), t
    For t = 0 To EVAL_TERM_COUNT - 1
        Dim As Integer wv = (mgT(0, t) * phase + egT(0, t) * (24 - phase)) \ 24
        Dim As Integer bv = (mgT(1, t) * phase + egT(1, t) * (24 - phase)) \ 24
        terms(t) = wv - bv
    Next
End Sub

'' =====================================================================
'' Transposition table
'' =====================================================================
Type TTEntry
    key    As ULongInt
    score  As Short
    depth  As Byte
    flag   As UByte          '' TT_EXACT / TT_LOWER / TT_UPPER
    fromSq As UByte
    toSq   As UByte
    promo  As UByte
    pad    As UByte
End Type

Const TT_EXACT = 1
Const TT_LOWER = 2
Const TT_UPPER = 3
Const TT_BITS = 20                       '' 1M entries x 16 bytes = 16 MB

Dim Shared TTable As TTEntry Ptr = 0
Dim Shared TTMask As ULongInt = 0

Private Sub TT_Init()
    If TTable Then Exit Sub
    Dim As Integer n = 1 Shl TT_BITS
    TTable = CAllocate(n * SizeOf(TTEntry))
    TTMask = n - 1
End Sub

Private Sub TT_Clear()
    If TTable = 0 Then Exit Sub
    Clear *TTable, 0, (TTMask + 1) * SizeOf(TTEntry)
End Sub

Private Function ScoreToTT(ByVal score As Integer, ByVal ply As Integer) As Integer
    If score > SCORE_MATE - 200 Then Return score + ply
    If score < -SCORE_MATE + 200 Then Return score - ply
    Return score
End Function

Private Function ScoreFromTT(ByVal score As Integer, ByVal ply As Integer) As Integer
    If score > SCORE_MATE - 200 Then Return score - ply
    If score < -SCORE_MATE + 200 Then Return score + ply
    Return score
End Function

Private Sub TT_Store(ByVal key As ULongInt, ByVal depth As Integer, ByVal score As Integer, _
                     ByVal flag As Integer, ByRef m As ChessMove, ByVal ply As Integer)
    Dim As TTEntry Ptr e = @TTable[key And TTMask]
    Dim As Boolean sameKey = (e->key = key)
    '' Replace if different position, not shallower, or exact.
    If (Not sameKey) OrElse depth >= e->depth OrElse flag = TT_EXACT Then
        '' Keep the old best move if this search did not find one.
        If m.piece <> PC_EMPTY OrElse Not sameKey Then
            e->fromSq = m.fromSq : e->toSq = m.toSq : e->promo = m.promotion
        End If
        e->key = key
        e->depth = IIf(depth > 127, 127, depth)
        e->score = ScoreToTT(score, ply)
        e->flag = flag
    End If
End Sub

'' =====================================================================
'' Search
'' =====================================================================
Type SearchState
    nodes      As ULongInt
    startTime  As Double
    timeLimit  As Double             '' seconds; 0 = none
    stopped    As Boolean
    prm        As EngineParams
    engineSide As Integer
    killers(0 To MAX_SEARCH_PLY, 0 To 1) As ChessMove
    history(0 To 15, 0 To 127) As Integer
    pvLen(0 To MAX_SEARCH_PLY) As Integer
    pv(0 To MAX_SEARCH_PLY, 0 To MAX_SEARCH_PLY) As ChessMove
End Type

Dim Shared Srch As SearchState

'' Stop request from another thread (protected by a mutex).
Dim Shared StopMutex As Any Ptr = 0
Dim Shared StopRequested As Integer = 0

Private Function ExternalStop() As Boolean
    If StopMutex = 0 Then Return False
    MutexLock StopMutex
    Dim As Integer v = StopRequested
    MutexUnlock StopMutex
    Return v <> 0
End Function

Private Sub CheckTime()
    If Srch.timeLimit > 0 AndAlso Timer - Srch.startTime > Srch.timeLimit Then Srch.stopped = True
    If ExternalStop() Then Srch.stopped = True
End Sub

Private Function DrawScore(ByRef p As Position) As Integer
    '' Contempt: the engine's side dislikes (or likes) draws.
    If p.sideToMove = Srch.engineSide Then Return -Srch.prm.contempt
    Return Srch.prm.contempt
End Function

'' Repetition (once is enough inside a search) or fifty-move rule.
Private Function IsSearchDraw(ByRef p As Position) As Boolean
    If p.halfmoveClock >= 100 Then Return True
    Dim As Integer oldest = p.historyCount - p.halfmoveClock
    If oldest < 0 Then oldest = 0
    Dim As Integer i = p.historyCount - 2
    Do While i >= oldest
        If p.undoStack(i).hash = p.hash Then Return True
        i -= 2
    Loop
    Return False
End Function

Private Function Evaluate(ByRef p As Position) As Integer
    Dim As Integer w = EvaluateWhite(p, Srch.prm.style, Srch.engineSide)
    Return IIf(p.sideToMove = SIDE_WHITE, w, -w)
End Function

Private Function HasNonPawnMaterial(ByRef p As Position, ByVal side As Integer) As Boolean
    Dim As Integer s
    For s = 0 To 119
        If SQ_OFFBOARD(s) Then Continue For
        Dim As Integer pc = p.board(s)
        If pc <> PC_EMPTY AndAlso PIECE_COLOR(pc) = side Then
            Select Case PIECE_TYPE(pc)
            Case PT_KNIGHT, PT_BISHOP, PT_ROOK, PT_QUEEN : Return True
            End Select
        End If
    Next
    Return False
End Function

'' Gives every move an ordering score (higher = searched earlier).
Private Sub ScoreMoves(ByRef list As MoveList, scores() As Integer, ByRef ttMove As ChessMove, ByVal ply As Integer)
    Dim As Integer i
    For i = 0 To list.count - 1
        With list.moves(i)
            If ttMove.piece <> PC_EMPTY AndAlso .fromSq = ttMove.fromSq AndAlso .toSq = ttMove.toSq _
               AndAlso .promotion = ttMove.promotion Then
                scores(i) = 10000000
            ElseIf (.flags And (MF_CAPTURE Or MF_PROMOTION)) <> 0 Then
                '' MVV-LVA: most valuable victim, least valuable attacker
                scores(i) = 1000000 + PieceVal(PIECE_TYPE(.captured)) * 10 - PieceVal(PIECE_TYPE(.piece)) \ 10
                If .promotion = PT_QUEEN Then scores(i) += 9000
            ElseIf ply <= MAX_SEARCH_PLY AndAlso Move_Equal(list.moves(i), Srch.killers(ply, 0)) Then
                scores(i) = 900000
            ElseIf ply <= MAX_SEARCH_PLY AndAlso Move_Equal(list.moves(i), Srch.killers(ply, 1)) Then
                scores(i) = 800000
            Else
                scores(i) = Srch.history(.piece, .toSq)
            End If
        End With
    Next
End Sub

'' Moves the best remaining move to position i (selection sort step).
Private Sub PickMove(ByRef list As MoveList, scores() As Integer, ByVal i As Integer)
    Dim As Integer best = i, j
    For j = i + 1 To list.count - 1
        If scores(j) > scores(best) Then best = j
    Next
    If best <> i Then
        Swap list.moves(i), list.moves(best)
        Swap scores(i), scores(best)
    End If
End Sub

Private Function Quiesce(ByRef p As Position, ByVal alpha As Integer, ByVal beta As Integer, ByVal ply As Integer) As Integer
    Srch.nodes += 1
    If (Srch.nodes And 1023) = 0 Then CheckTime()
    If Srch.stopped Then Return 0
    If ply >= MAX_SEARCH_PLY - 1 Then Return Evaluate(p)

    Dim As Boolean inCheck = Pos_InCheck(p)
    Dim As Integer standPat = -SCORE_INF
    If Not inCheck Then
        standPat = Evaluate(p)
        If Not Srch.prm.useQuiescence Then Return standPat
        If standPat >= beta Then Return standPat
        If standPat > alpha Then alpha = standPat
    End If

    Dim As MoveList list
    Pos_GeneratePseudo(p, list)
    Dim As Integer scores(0 To MAX_MOVES - 1)
    Dim As ChessMove noMove
    ScoreMoves(list, scores(), noMove, ply)
    Dim As Integer i, legal = 0, best = standPat
    For i = 0 To list.count - 1
        PickMove(list, scores(), i)
        Dim As ChessMove m = list.moves(i)
        Dim As Boolean tactical = (m.flags And (MF_CAPTURE Or MF_PROMOTION)) <> 0
        '' Out of check every move is searched; otherwise only captures/promotions.
        If Not inCheck Then
            If Not tactical Then Continue For
            '' Delta pruning: even winning this piece cannot raise alpha.
            If m.promotion = PT_NONE AndAlso standPat + PieceVal(PIECE_TYPE(m.captured)) + 200 < alpha Then Continue For
        End If
        Pos_MakeMove(p, m)
        If Pos_LastMoveWasIllegal(p) Then
            Pos_UnmakeMove(p)
            Continue For
        End If
        legal += 1
        Dim As Integer score = -Quiesce(p, -beta, -alpha, ply + 1)
        Pos_UnmakeMove(p)
        If Srch.stopped Then Return 0
        If score > best Then best = score
        If score >= beta Then Return score
        If score > alpha Then alpha = score
    Next
    If inCheck AndAlso legal = 0 Then Return -SCORE_MATE + ply
    Return best
End Function

Private Function Negamax(ByRef p As Position, ByVal depth As Integer, ByVal alpha As Integer, _
                         ByVal beta As Integer, ByVal ply As Integer, ByVal allowNull As Boolean) As Integer
    Srch.pvLen(ply) = ply
    Srch.nodes += 1
    If (Srch.nodes And 1023) = 0 Then CheckTime()
    If Srch.stopped Then Return 0

    If ply > 0 Then
        If IsSearchDraw(p) Then Return DrawScore(p)
        '' Mate distance pruning
        If alpha < -SCORE_MATE + ply Then alpha = -SCORE_MATE + ply
        If beta > SCORE_MATE - ply - 1 Then beta = SCORE_MATE - ply - 1
        If alpha >= beta Then Return alpha
    End If
    If ply >= MAX_SEARCH_PLY - 2 Then Return Evaluate(p)

    Dim As Boolean inCheck = Pos_InCheck(p)
    If inCheck Then depth += 1                         '' check extension
    If depth <= 0 Then Return Quiesce(p, alpha, beta, ply)

    Dim As Boolean isPV = (beta - alpha) > 1
    Dim As Integer alphaOrig = alpha

    '' Transposition table
    Dim As ChessMove ttMove
    Dim As TTEntry Ptr e = @TTable[p.hash And TTMask]
    If e->key = p.hash Then
        ttMove.fromSq = e->fromSq : ttMove.toSq = e->toSq : ttMove.promotion = e->promo
        ttMove.piece = p.board(e->fromSq)
        If ply > 0 AndAlso Not isPV AndAlso e->depth >= depth Then
            Dim As Integer ts = ScoreFromTT(e->score, ply)
            Select Case e->flag
            Case TT_EXACT : Return ts
            Case TT_LOWER : If ts >= beta Then Return ts
            Case TT_UPPER : If ts <= alpha Then Return ts
            End Select
        End If
    End If

    '' Null-move pruning: if passing still keeps us above beta, this
    '' position is good enough to cut.
    Dim As Boolean nullOk = allowNull AndAlso (Not isPV) AndAlso (Not inCheck)
    If depth < 3 OrElse ply = 0 Then nullOk = False
    If nullOk AndAlso HasNonPawnMaterial(p, p.sideToMove) Then
        If Evaluate(p) >= beta Then
            Pos_MakeNullMove(p)
            Dim As Integer nullScore = -Negamax(p, depth - 3, -beta, -beta + 1, ply + 1, False)
            Pos_UnmakeMove(p)
            If Srch.stopped Then Return 0
            If nullScore >= beta AndAlso nullScore < SCORE_MATE - 200 Then Return beta
        End If
    End If

    Dim As MoveList list
    Pos_GeneratePseudo(p, list)
    Dim As Integer scores(0 To MAX_MOVES - 1)
    ScoreMoves(list, scores(), ttMove, ply)

    Dim As Integer i, legal = 0, bestScore = -SCORE_INF
    Dim As ChessMove bestMove
    For i = 0 To list.count - 1
        PickMove(list, scores(), i)
        Dim As ChessMove m = list.moves(i)
        Pos_MakeMove(p, m)
        If Pos_LastMoveWasIllegal(p) Then
            Pos_UnmakeMove(p)
            Continue For
        End If
        legal += 1
        Dim As Boolean quiet = (m.flags And (MF_CAPTURE Or MF_PROMOTION)) = 0
        Dim As Boolean givesCheck = Pos_InCheck(p)
        Dim As Integer score

        If legal = 1 Then
            score = -Negamax(p, depth - 1, -beta, -alpha, ply + 1, True)
        Else
            '' Late move reductions for quiet moves searched late.
            Dim As Integer red = 0
            Dim As Boolean lateQuiet = quiet AndAlso (Not inCheck) AndAlso (Not givesCheck)
            If depth < 3 OrElse legal <= 4 OrElse scores(i) >= 800000 Then lateQuiet = False
            If lateQuiet Then
                red = IIf(legal > 12, 2, 1)
            End If
            score = -Negamax(p, depth - 1 - red, -alpha - 1, -alpha, ply + 1, True)
            If score > alpha AndAlso (red > 0 OrElse score < beta) Then
                score = -Negamax(p, depth - 1, -beta, -alpha, ply + 1, True)
            End If
        End If
        Pos_UnmakeMove(p)
        If Srch.stopped Then Return 0

        If score > bestScore Then
            bestScore = score
            bestMove = m
            If score > alpha Then
                alpha = score
                '' Update the principal variation.
                Srch.pv(ply, ply) = m
                Dim As Integer j
                For j = ply + 1 To Srch.pvLen(ply + 1) - 1
                    Srch.pv(ply, j) = Srch.pv(ply + 1, j)
                Next
                Srch.pvLen(ply) = IIf(Srch.pvLen(ply + 1) > ply + 1, Srch.pvLen(ply + 1), ply + 1)
                If score >= beta Then
                    If quiet Then
                        If Not Move_Equal(Srch.killers(ply, 0), m) Then
                            Srch.killers(ply, 1) = Srch.killers(ply, 0)
                            Srch.killers(ply, 0) = m
                        End If
                        Srch.history(m.piece, m.toSq) += depth * depth
                        If Srch.history(m.piece, m.toSq) > 400000 Then Srch.history(m.piece, m.toSq) \= 2
                    End If
                    TT_Store(p.hash, depth, score, TT_LOWER, m, ply)
                    Return score
                End If
            End If
        End If
    Next

    If legal = 0 Then
        If inCheck Then Return -SCORE_MATE + ply
        Return DrawScore(p)       '' stalemate
    End If
    TT_Store(p.hash, depth, bestScore, IIf(bestScore > alphaOrig, TT_EXACT, TT_UPPER), bestMove, ply)
    Return bestScore
End Function

'' Chooses among the root moves the way a human of the level would.
Private Function ChooseHumanLike(ByRef p As Position, rootMoves() As ChessMove, ByVal n As Integer, _
                                 ByVal depth As Integer, ByRef chosenScore As Integer) As Integer
    Dim As Integer exact(0 To MAX_MOVES - 1), i, best = -SCORE_INF
    '' Exact score of every move (full window, small depth).
    For i = 0 To n - 1
        Pos_MakeMove(p, rootMoves(i))
        exact(i) = -Negamax(p, depth - 1, -SCORE_INF, SCORE_INF, 1, True)
        Pos_UnmakeMove(p)
        If Srch.stopped Then Return -1
        exact(i) += RandRange(-Srch.prm.noise, Srch.prm.noise)
        If exact(i) > best Then best = exact(i)
    Next
    Dim As Integer margin = Srch.prm.margin
    Dim As Single temp = Srch.prm.temperature
    If RandFloat() < Srch.prm.blunderChance Then
        margin *= 2 : temp *= 3                            '' an "off" moment
    End If
    '' Never throw away a forced mate the engine has found.
    If best > SCORE_MATE - 200 Then margin = 0
    Dim As Double weights(0 To MAX_MOVES - 1), total = 0
    For i = 0 To n - 1
        weights(i) = 0
        If exact(i) >= best - margin Then
            weights(i) = Exp((exact(i) - best) / IIf(temp > 1, temp, 1))
            total += weights(i)
        End If
    Next
    Dim As Double pick = RandFloat() * total
    For i = 0 To n - 1
        If weights(i) > 0 Then
            pick -= weights(i)
            If pick <= 0 Then
                chosenScore = exact(i)
                Return i
            End If
        End If
    Next
    For i = 0 To n - 1
        If exact(i) = best Then chosenScore = best : Return i
    Next
    Return 0
End Function

Function Engine_Search(ByRef p As Position, ByRef prm As EngineParams, ByRef res As EngineResult) As Boolean
    TT_Init()
    InitStyles()
    Srch.prm = prm
    Srch.nodes = 0
    Srch.stopped = False
    Srch.startTime = Timer
    Srch.timeLimit = prm.timeLimitMs / 1000.0
    Srch.engineSide = p.sideToMove
    EngRng Xor= CULngInt(Timer * 1000003)
    If EngRng = 0 Then EngRng = 88172645463325252ull
    res.nodes = 0 : res.depth = 0 : res.pvLen = 0 : res.score = 0
    res.bestMove.piece = PC_EMPTY
    res.fromBook = False

    '' Opening book
    Dim As Integer gamePly = (p.fullmoveNumber - 1) * 2 + IIf(p.sideToMove = SIDE_BLACK, 1, 0)
    If prm.bookPlies > 0 AndAlso gamePly < prm.bookPlies Then
        Dim As ChessMove bm
        If Book_Probe(p, RandFloat(), bm) Then
            res.bestMove = bm
            res.fromBook = True
            res.pvLen = 1
            res.pv(0) = bm
            res.timeMs = (Timer - Srch.startTime) * 1000
            Return True
        End If
    End If

    '' Search on a private copy so the caller's position is never touched.
    Static work As Position
    work = p

    Dim As MoveList rootList
    Pos_GenerateLegal(work, rootList)
    If rootList.count = 0 Then Return False
    Dim As ChessMove rootMoves(0 To MAX_MOVES - 1)
    Dim As Integer rootScores(0 To MAX_MOVES - 1)
    Dim As Integer n = rootList.count, i, j
    For i = 0 To n - 1
        rootMoves(i) = rootList.moves(i)
    Next
    res.bestMove = rootMoves(0)

    '' Initial order: captures and promotions first.
    Dim As ChessMove noMove
    Dim As Integer orderScores(0 To MAX_MOVES - 1)
    ScoreMoves(rootList, orderScores(), noMove, 0)
    For i = 0 To n - 1
        rootMoves(i) = rootList.moves(i)
        rootScores(i) = orderScores(i)
    Next
    For i = 0 To n - 2                                   '' simple sort by score
        For j = i + 1 To n - 1
            If rootScores(j) > rootScores(i) Then
                Swap rootScores(i), rootScores(j)
                Swap rootMoves(i), rootMoves(j)
            End If
        Next
    Next
    res.bestMove = rootMoves(0)

    Dim As Integer killPly
    For killPly = 0 To MAX_SEARCH_PLY
        Srch.killers(killPly, 0) = noMove
        Srch.killers(killPly, 1) = noMove
    Next

    Dim As Integer depth, completedDepth = 0, bestScore = 0
    Dim As Integer maxDepth = prm.maxDepth
    If maxDepth < 1 Then maxDepth = 1
    If maxDepth > MAX_SEARCH_PLY - 4 Then maxDepth = MAX_SEARCH_PLY - 4

    For depth = 1 To maxDepth
        Dim As Integer alpha = -SCORE_INF, beta = SCORE_INF
        Dim As Integer iterBest = -1, iterScore = -SCORE_INF, searched = 0
        For i = 0 To n - 1
            Pos_MakeMove(work, rootMoves(i))
            Dim As Integer score
            If i = 0 Then
                score = -Negamax(work, depth - 1, -beta, -alpha, 1, True)
            Else
                score = -Negamax(work, depth - 1, -alpha - 1, -alpha, 1, True)
                If score > alpha AndAlso Not Srch.stopped Then
                    score = -Negamax(work, depth - 1, -beta, -alpha, 1, True)
                End If
            End If
            Pos_UnmakeMove(work)
            If Srch.stopped Then Exit For
            searched += 1
            rootScores(i) = IIf(score > alpha OrElse i = 0, score, -SCORE_INF + i)
            If score > iterScore Then
                iterScore = score
                iterBest = i
                '' Root PV
                Srch.pv(0, 0) = rootMoves(i)
                For j = 1 To Srch.pvLen(1) - 1
                    Srch.pv(0, j) = Srch.pv(1, j)
                Next
                Srch.pvLen(0) = IIf(Srch.pvLen(1) > 1, Srch.pvLen(1), 1)
            End If
            If score > alpha Then alpha = score
        Next

        '' The first root move is the previous best, so a partly searched
        '' iteration is still usable once that move has been searched.
        If iterBest >= 0 AndAlso (Not Srch.stopped OrElse searched >= 1) Then
            res.bestMove = rootMoves(iterBest)
            bestScore = iterScore
            res.pvLen = IIf(Srch.pvLen(0) > MAX_PV, MAX_PV, Srch.pvLen(0))
            For j = 0 To res.pvLen - 1
                res.pv(j) = Srch.pv(0, j)
            Next
            If Not Srch.stopped Then completedDepth = depth
            '' Best move first for the next iteration, others by score.
            Dim As ChessMove bm = rootMoves(iterBest)
            Dim As Integer bs = rootScores(iterBest)
            For j = iterBest To 1 Step -1
                rootMoves(j) = rootMoves(j - 1)
                rootScores(j) = rootScores(j - 1)
            Next
            rootMoves(0) = bm
            rootScores(0) = bs
        End If
        If Srch.stopped Then Exit For
        '' Found a forced mate: no need to search deeper.
        If Abs(bestScore) > SCORE_MATE - 200 AndAlso SCORE_MATE - Abs(bestScore) <= depth Then Exit For
        '' Not enough time left for another (roughly 3x longer) iteration.
        If Srch.timeLimit > 0 AndAlso Timer - Srch.startTime > Srch.timeLimit * 0.4 Then Exit For
        If n = 1 AndAlso depth >= 2 Then Exit For
    Next

    '' Lower levels: pick a natural, sometimes imperfect move.
    If prm.temperature > 0 AndAlso n > 1 Then
        Dim As Integer d = IIf(completedDepth > 0, completedDepth, 1)
        Dim As Boolean savedStop = Srch.stopped
        Srch.stopped = False
        Srch.timeLimit = 0                    '' cheap at these depths
        Dim As Integer chosenScore
        Dim As Integer k = ChooseHumanLike(work, rootMoves(), n, d, chosenScore)
        If k >= 0 AndAlso Not Srch.stopped Then
            If Not Move_Equal(rootMoves(k), res.bestMove) Then res.pvLen = 1 : res.pv(0) = rootMoves(k)
            res.bestMove = rootMoves(k)
            bestScore = chosenScore
        End If
        Srch.stopped = savedStop
    End If

    '' Safety net: the move must be legal in the original position.
    Dim As ChessMove check
    If Not Pos_FindLegalMove(work, res.bestMove.fromSq, res.bestMove.toSq, res.bestMove.promotion, check) Then
        res.bestMove = rootList.moves(0)
    Else
        res.bestMove = check
    End If
    res.score = bestScore
    res.depth = completedDepth
    res.nodes = Srch.nodes
    res.timeMs = (Timer - Srch.startTime) * 1000
    Return True
End Function

Function Engine_ShouldResign(ByRef p As Position, ByVal score As Integer, _
                             ByRef losingStreak As Integer) As Boolean
    If score <= -900 Then losingStreak += 1 Else losingStreak = 0
    '' Can the opponent still checkmate? (Never resign into a dead draw.)
    Dim As Integer opp = p.sideToMove Xor 1, s, minors = 0
    Dim As Boolean canMate = False
    For s = 0 To 119
        If SQ_OFFBOARD(s) Then Continue For
        Dim As Integer pc = p.board(s)
        If pc = PC_EMPTY OrElse PIECE_COLOR(pc) <> opp Then Continue For
        Select Case PIECE_TYPE(pc)
        Case PT_PAWN, PT_ROOK, PT_QUEEN : canMate = True
        Case PT_KNIGHT, PT_BISHOP : minors += 1
        End Select
    Next
    If minors >= 2 Then canMate = True
    If Not canMate Then Return False
    If score <= -SCORE_MATE + 40 Then Return True          '' forced mate against us
    Return losingStreak >= 3
End Function

Sub Engine_NewGame()
    TT_Init()
    TT_Clear()
    Dim As Integer a, b
    For a = 0 To 15
        For b = 0 To 127
            Srch.history(a, b) = 0
        Next
    Next
End Sub

'' =====================================================================
'' Background thinking
'' =====================================================================
Dim Shared AsyncPos As Position
Dim Shared AsyncParams As EngineParams
Dim Shared AsyncResult As EngineResult
Dim Shared AsyncThread As Any Ptr = 0
Dim Shared AsyncDone As Integer = 0
Dim Shared AsyncMutex As Any Ptr = 0

Private Sub EnsureMutexes()
    If AsyncMutex = 0 Then AsyncMutex = MutexCreate()
    If StopMutex = 0 Then StopMutex = MutexCreate()
End Sub

Private Sub SetStopRequest(ByVal v As Integer)
    MutexLock StopMutex
    StopRequested = v
    MutexUnlock StopMutex
End Sub

Private Sub EngineThreadProc(ByVal userData As Any Ptr)
    Dim As EngineResult r
    Engine_Search(AsyncPos, AsyncParams, r)
    MutexLock AsyncMutex
    AsyncResult = r
    AsyncDone = 1
    MutexUnlock AsyncMutex
End Sub

Sub Engine_StartAsync(ByRef p As Position, ByRef prm As EngineParams)
    EnsureMutexes()
    Engine_StopAsync()
    TT_Init()
    AsyncPos = p
    AsyncParams = prm
    AsyncDone = 0
    SetStopRequest(0)
    '' Generous stack: the search recurses with move lists on the stack.
    AsyncThread = ThreadCreate(@EngineThreadProc, 0, 8 * 1024 * 1024)
    If AsyncThread = 0 Then
        '' Threads unavailable: think synchronously instead.
        EngineThreadProc(0)
    End If
End Sub

Function Engine_PollAsync(ByRef res As EngineResult) As Boolean
    If AsyncMutex = 0 Then Return False
    Dim As Integer done
    MutexLock AsyncMutex
    done = AsyncDone
    If done Then
        res = AsyncResult
        AsyncDone = 0
    End If
    MutexUnlock AsyncMutex
    If done = 0 Then Return False
    If AsyncThread Then ThreadWait AsyncThread : AsyncThread = 0
    Return True
End Function

Function Engine_IsThinking() As Boolean
    If AsyncMutex = 0 Then Return False
    If AsyncThread = 0 Then
        MutexLock AsyncMutex
        Dim As Integer d = AsyncDone
        MutexUnlock AsyncMutex
        Return d <> 0          '' synchronous fallback finished but not collected
    End If
    Return True
End Function

Sub Engine_RequestStop()
    If StopMutex Then SetStopRequest(1)
End Sub

Sub Engine_StopAsync()
    If AsyncThread Then
        SetStopRequest(1)
        ThreadWait AsyncThread
        AsyncThread = 0
    End If
    If AsyncMutex Then
        MutexLock AsyncMutex
        AsyncDone = 0
        MutexUnlock AsyncMutex
    End If
    If StopMutex Then SetStopRequest(0)
End Sub

Sub Engine_Shutdown()
    Engine_StopAsync()
    If TTable Then Deallocate TTable : TTable = 0
    If AsyncMutex Then MutexDestroy AsyncMutex : AsyncMutex = 0
    If StopMutex Then MutexDestroy StopMutex : StopMutex = 0
End Sub
