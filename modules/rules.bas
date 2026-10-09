'' =====================================================================
'' BeginnerChess - rules.bas
'' Implementation of the chess rules. See rules.bi for the interface.
'' =====================================================================
#include once "rules.bi"

'' ---------------------------------------------------------------------
'' Lookup tables (private to this module)
'' ---------------------------------------------------------------------
Dim Shared KnightOffsets(0 To 7) As Integer = {33, 31, 18, 14, -33, -31, -18, -14}
Dim Shared KingOffsets(0 To 7)   As Integer = {1, -1, 16, -16, 15, 17, -15, -17}
Dim Shared BishopDirs(0 To 3)    As Integer = {15, 17, -15, -17}
Dim Shared RookDirs(0 To 3)      As Integer = {1, -1, 16, -16}

'' Castling rights that survive a move touching each square.
Dim Shared CastleKeepMask(0 To 127) As Integer

'' Zobrist hashing keys
Dim Shared ZobPiece(0 To 15, 0 To 127) As ULongInt
Dim Shared ZobCastle(0 To 15) As ULongInt
Dim Shared ZobEpFile(0 To 7) As ULongInt
Dim Shared ZobSide As ULongInt

Dim Shared RulesReady As Boolean = False

'' Deterministic 64-bit pseudo random generator (xorshift64*), so that
'' hash values are identical on every platform and every run.
Dim Shared ZobSeed As ULongInt = &h9E3779B97F4A7C15ull

Private Function NextRandom64() As ULongInt
    ZobSeed Xor= (ZobSeed Shr 12)
    ZobSeed Xor= (ZobSeed Shl 25)
    ZobSeed Xor= (ZobSeed Shr 27)
    Return ZobSeed * &h2545F4914F6CDD1Dull
End Function

Sub Rules_Init()
    If RulesReady Then Exit Sub

    Dim As Integer pc, s, i
    For pc = 0 To 15
        For s = 0 To 127
            ZobPiece(pc, s) = NextRandom64()
        Next
    Next
    For i = 0 To 15
        ZobCastle(i) = NextRandom64()
    Next
    For i = 0 To 7
        ZobEpFile(i) = NextRandom64()
    Next
    ZobSide = NextRandom64()

    For s = 0 To 127
        CastleKeepMask(s) = 15
    Next
    CastleKeepMask(SQ_A1) = 15 And (Not CR_WHITE_QUEEN)
    CastleKeepMask(SQ_H1) = 15 And (Not CR_WHITE_KING)
    CastleKeepMask(SQ_E1) = 15 And (Not (CR_WHITE_KING Or CR_WHITE_QUEEN))
    CastleKeepMask(SQ_A8) = 15 And (Not CR_BLACK_QUEEN)
    CastleKeepMask(SQ_H8) = 15 And (Not CR_BLACK_KING)
    CastleKeepMask(SQ_E8) = 15 And (Not (CR_BLACK_KING Or CR_BLACK_QUEEN))

    RulesReady = True
End Sub

'' ---------------------------------------------------------------------
'' Small helpers
'' ---------------------------------------------------------------------
Function Sq_Name(ByVal sq As Integer) As String
    If sq < 0 OrElse SQ_OFFBOARD(sq) Then Return "-"
    Return Chr(Asc("a") + SQ_FILE(sq)) & Chr(Asc("1") + SQ_RANK(sq))
End Function

'' Parses "e4" -> square index, or NO_SQUARE on failure.
Function Sq_Parse(ByRef s As Const String) As Integer
    If Len(s) <> 2 Then Return NO_SQUARE
    Dim As Integer f = Asc(LCase(s), 1) - Asc("a")
    Dim As Integer r = Asc(s, 2) - Asc("1")
    If f < 0 OrElse f > 7 OrElse r < 0 OrElse r > 7 Then Return NO_SQUARE
    Return MAKE_SQ(f, r)
End Function

Function Piece_Char(ByVal pc As Integer) As String
    Dim As String letters = " PNBRQK"
    Dim As Integer t = PIECE_TYPE(pc)
    If t < PT_PAWN OrElse t > PT_KING Then Return " "
    If PIECE_COLOR(pc) = SIDE_WHITE Then Return Mid(letters, t + 1, 1)
    Return LCase(Mid(letters, t + 1, 1))
End Function

Function Move_IsNull(ByRef m As ChessMove) As Boolean
    Return m.piece = PC_EMPTY
End Function

Function Move_Equal(ByRef a As ChessMove, ByRef b As ChessMove) As Boolean
    Return a.fromSq = b.fromSq AndAlso a.toSq = b.toSq AndAlso a.promotion = b.promotion
End Function

'' True if the side to move has a pawn that could capture onto the
'' current en-passant square. Only then does the en-passant square change
'' the position for repetition purposes, so only then is it hashed.
Private Function EpIsHashable(ByRef p As Position) As Boolean
    Dim As Integer ep = p.epSquare
    If ep = NO_SQUARE Then Return False
    Dim As Integer s1, s2, pawn
    If p.sideToMove = SIDE_WHITE Then
        s1 = ep - 15 : s2 = ep - 17 : pawn = PC_WP
    Else
        s1 = ep + 15 : s2 = ep + 17 : pawn = PC_BP
    End If
    If Not SQ_OFFBOARD(s1) AndAlso p.board(s1) = pawn Then Return True
    If Not SQ_OFFBOARD(s2) AndAlso p.board(s2) = pawn Then Return True
    Return False
End Function

'' ---------------------------------------------------------------------
'' Position setup
'' ---------------------------------------------------------------------
Sub Pos_Clear(ByRef p As Position)
    Rules_Init()
    Dim As Integer s
    For s = 0 To 127
        p.board(s) = PC_EMPTY
    Next
    p.sideToMove = SIDE_WHITE
    p.castling = 0
    p.epSquare = NO_SQUARE
    p.halfmoveClock = 0
    p.fullmoveNumber = 1
    p.kingSq(0) = NO_SQUARE
    p.kingSq(1) = NO_SQUARE
    p.historyCount = 0
    p.hash = Pos_ComputeHash(p)
End Sub

Sub Pos_SetStart(ByRef p As Position)
    Dim As String errMsg
    Pos_LoadFEN(p, START_FEN, errMsg)
End Sub

Function Pos_ComputeHash(ByRef p As Position) As ULongInt
    Rules_Init()
    Dim As ULongInt h = 0
    Dim As Integer s
    For s = 0 To 127
        If Not SQ_OFFBOARD(s) AndAlso p.board(s) <> PC_EMPTY Then
            h Xor= ZobPiece(p.board(s), s)
        End If
    Next
    h Xor= ZobCastle(p.castling And 15)
    If EpIsHashable(p) Then h Xor= ZobEpFile(SQ_FILE(p.epSquare))
    If p.sideToMove = SIDE_BLACK Then h Xor= ZobSide
    Return h
End Function

'' Splits a string on runs of spaces/tabs.
Private Function SplitFields(ByRef text As Const String, fields() As String) As Integer
    Dim As Integer n = 0, i
    Dim As String cur = ""
    For i = 1 To Len(text)
        Dim As String c = Mid(text, i, 1)
        If c = " " OrElse c = Chr(9) Then
            If Len(cur) > 0 Then
                If n <= UBound(fields) Then fields(n) = cur
                n += 1
                cur = ""
            End If
        Else
            cur &= c
        End If
    Next
    If Len(cur) > 0 Then
        If n <= UBound(fields) Then fields(n) = cur
        n += 1
    End If
    Return n
End Function

Private Function IsAllDigits(ByRef s As Const String) As Boolean
    If Len(s) = 0 Then Return False
    Dim As Integer i
    For i = 1 To Len(s)
        Dim As Integer c = Asc(s, i)
        If c < Asc("0") OrElse c > Asc("9") Then Return False
    Next
    Return True
End Function

'' Loads a FEN string. On failure the position is left unchanged and
'' errMsg explains the problem in plain language.
Function Pos_LoadFEN(ByRef p As Position, ByRef fen As Const String, _
                     ByRef errMsg As String) As Boolean
    Rules_Init()
    errMsg = ""

    Dim As String fields(0 To 7)
    Dim As Integer nFields = SplitFields(fen, fields())
    If nFields < 4 Then
        errMsg = "A FEN needs at least 4 parts (pieces, side to move, castling, en passant)."
        Return False
    End If
    If nFields > 6 Then
        errMsg = "A FEN has at most 6 parts, but this text has " & nFields & "."
        Return False
    End If

    '' Build into a temporary position so a bad FEN changes nothing.
    Static tmp As Position
    Pos_Clear(tmp)

    '' --- 1. Piece placement ---
    Dim As String placement = fields(0)
    Dim As Integer rank = 7, file = 0, i
    Dim As Integer kings(0 To 1) = {0, 0}
    For i = 1 To Len(placement)
        Dim As String c = Mid(placement, i, 1)
        If c = "/" Then
            If file <> 8 Then
                errMsg = "Rank " & (rank + 1) & " in the FEN does not have exactly 8 squares."
                Return False
            End If
            rank -= 1
            file = 0
            If rank < 0 Then
                errMsg = "The FEN board has more than 8 ranks."
                Return False
            End If
        ElseIf c >= "1" AndAlso c <= "8" Then
            file += Val(c)
            If file > 8 Then
                errMsg = "Rank " & (rank + 1) & " in the FEN has more than 8 squares."
                Return False
            End If
        Else
            Dim As Integer pos1 = InStr("PNBRQKpnbrqk", c)
            If pos1 = 0 Then
                errMsg = "Unknown piece letter '" & c & "' in the FEN."
                Return False
            End If
            If file > 7 Then
                errMsg = "Rank " & (rank + 1) & " in the FEN has more than 8 squares."
                Return False
            End If
            Dim As Integer side = IIf(pos1 > 6, SIDE_BLACK, SIDE_WHITE)
            Dim As Integer pt = ((pos1 - 1) Mod 6) + 1
            Dim As Integer s = MAKE_SQ(file, rank)
            tmp.board(s) = MAKE_PIECE(side, pt)
            If pt = PT_KING Then
                kings(side) += 1
                tmp.kingSq(side) = s
            End If
            If pt = PT_PAWN AndAlso (rank = 0 OrElse rank = 7) Then
                errMsg = "Pawns cannot stand on the first or last rank (found one on " & Sq_Name(s) & ")."
                Return False
            End If
            file += 1
        End If
    Next
    If rank <> 0 OrElse file <> 8 Then
        errMsg = "The FEN board must describe exactly 8 ranks of 8 squares."
        Return False
    End If
    If kings(SIDE_WHITE) <> 1 OrElse kings(SIDE_BLACK) <> 1 Then
        errMsg = "Each side must have exactly one king."
        Return False
    End If

    '' --- 2. Side to move ---
    Select Case LCase(fields(1))
    Case "w" : tmp.sideToMove = SIDE_WHITE
    Case "b" : tmp.sideToMove = SIDE_BLACK
    Case Else
        errMsg = "The side to move must be 'w' or 'b'."
        Return False
    End Select

    '' --- 3. Castling rights (rights not supported by the placement are dropped) ---
    tmp.castling = 0
    If fields(2) <> "-" Then
        For i = 1 To Len(fields(2))
            Select Case Mid(fields(2), i, 1)
            Case "K" : tmp.castling Or= CR_WHITE_KING
            Case "Q" : tmp.castling Or= CR_WHITE_QUEEN
            Case "k" : tmp.castling Or= CR_BLACK_KING
            Case "q" : tmp.castling Or= CR_BLACK_QUEEN
            Case Else
                errMsg = "Castling rights may only contain K, Q, k, q or '-'."
                Return False
            End Select
        Next
    End If
    If tmp.board(SQ_E1) <> PC_WK Then tmp.castling And= Not (CR_WHITE_KING Or CR_WHITE_QUEEN)
    If tmp.board(SQ_H1) <> PC_WR Then tmp.castling And= Not CR_WHITE_KING
    If tmp.board(SQ_A1) <> PC_WR Then tmp.castling And= Not CR_WHITE_QUEEN
    If tmp.board(SQ_E8) <> PC_BK Then tmp.castling And= Not (CR_BLACK_KING Or CR_BLACK_QUEEN)
    If tmp.board(SQ_H8) <> PC_BR Then tmp.castling And= Not CR_BLACK_KING
    If tmp.board(SQ_A8) <> PC_BR Then tmp.castling And= Not CR_BLACK_QUEEN

    '' --- 4. En-passant square (ignored if it is impossible) ---
    tmp.epSquare = NO_SQUARE
    If fields(3) <> "-" Then
        Dim As Integer ep = Sq_Parse(fields(3))
        If ep = NO_SQUARE Then
            errMsg = "The en-passant square '" & fields(3) & "' is not a valid square."
            Return False
        End If
        '' The pawn that just double-stepped must be in front of the ep square.
        If tmp.sideToMove = SIDE_WHITE Then
            If SQ_RANK(ep) = 5 AndAlso tmp.board(ep - 16) = PC_BP AndAlso _
               tmp.board(ep) = PC_EMPTY AndAlso tmp.board(ep + 16) = PC_EMPTY Then tmp.epSquare = ep
        Else
            If SQ_RANK(ep) = 2 AndAlso tmp.board(ep + 16) = PC_WP AndAlso _
               tmp.board(ep) = PC_EMPTY AndAlso tmp.board(ep - 16) = PC_EMPTY Then tmp.epSquare = ep
        End If
    End If

    '' --- 5/6. Move counters ---
    tmp.halfmoveClock = 0
    tmp.fullmoveNumber = 1
    If nFields >= 5 Then
        If Not IsAllDigits(fields(4)) Then
            errMsg = "The half-move clock must be a number."
            Return False
        End If
        tmp.halfmoveClock = ValInt(fields(4))
    End If
    If nFields >= 6 Then
        If Not IsAllDigits(fields(5)) Then
            errMsg = "The full-move number must be a number."
            Return False
        End If
        tmp.fullmoveNumber = ValInt(fields(5))
        If tmp.fullmoveNumber < 1 Then tmp.fullmoveNumber = 1
    End If

    '' --- Legality: the side NOT to move must not be in check ---
    Dim As Integer other = tmp.sideToMove Xor 1
    If Pos_IsSquareAttacked(tmp, tmp.kingSq(other), tmp.sideToMove) Then
        errMsg = "Illegal position: the side that is not to move is in check."
        Return False
    End If

    tmp.historyCount = 0
    tmp.hash = Pos_ComputeHash(tmp)

    '' Copy the board state (not the whole undo stack) into p.
    For i = 0 To 127
        p.board(i) = tmp.board(i)
    Next
    p.sideToMove = tmp.sideToMove
    p.castling = tmp.castling
    p.epSquare = tmp.epSquare
    p.halfmoveClock = tmp.halfmoveClock
    p.fullmoveNumber = tmp.fullmoveNumber
    p.kingSq(0) = tmp.kingSq(0)
    p.kingSq(1) = tmp.kingSq(1)
    p.hash = tmp.hash
    p.historyCount = 0
    Return True
End Function

Function Pos_GetFEN(ByRef p As Position) As String
    Dim As String result = ""
    Dim As Integer rank, file, empty
    For rank = 7 To 0 Step -1
        empty = 0
        For file = 0 To 7
            Dim As Integer pc = p.board(MAKE_SQ(file, rank))
            If pc = PC_EMPTY Then
                empty += 1
            Else
                If empty > 0 Then result &= Str(empty) : empty = 0
                result &= Piece_Char(pc)
            End If
        Next
        If empty > 0 Then result &= Str(empty)
        If rank > 0 Then result &= "/"
    Next

    result &= IIf(p.sideToMove = SIDE_WHITE, " w ", " b ")

    Dim As String cr = ""
    If p.castling And CR_WHITE_KING Then cr &= "K"
    If p.castling And CR_WHITE_QUEEN Then cr &= "Q"
    If p.castling And CR_BLACK_KING Then cr &= "k"
    If p.castling And CR_BLACK_QUEEN Then cr &= "q"
    If cr = "" Then cr = "-"
    result &= cr & " "

    If p.epSquare <> NO_SQUARE Then result &= Sq_Name(p.epSquare) Else result &= "-"
    result &= " " & p.halfmoveClock & " " & p.fullmoveNumber
    Return result
End Function

'' ---------------------------------------------------------------------
'' Attack detection
'' ---------------------------------------------------------------------
Function Pos_IsSquareAttacked(ByRef p As Position, ByVal sq As Integer, _
                              ByVal bySide As Integer) As Boolean
    Dim As Integer t, i, d, pc

    '' Pawns
    If bySide = SIDE_WHITE Then
        t = sq - 15 : If Not SQ_OFFBOARD(t) AndAlso p.board(t) = PC_WP Then Return True
        t = sq - 17 : If Not SQ_OFFBOARD(t) AndAlso p.board(t) = PC_WP Then Return True
    Else
        t = sq + 15 : If Not SQ_OFFBOARD(t) AndAlso p.board(t) = PC_BP Then Return True
        t = sq + 17 : If Not SQ_OFFBOARD(t) AndAlso p.board(t) = PC_BP Then Return True
    End If

    '' Knights
    Dim As Integer knight = MAKE_PIECE(bySide, PT_KNIGHT)
    For i = 0 To 7
        t = sq + KnightOffsets(i)
        If Not SQ_OFFBOARD(t) AndAlso p.board(t) = knight Then Return True
    Next

    '' King
    Dim As Integer king = MAKE_PIECE(bySide, PT_KING)
    For i = 0 To 7
        t = sq + KingOffsets(i)
        If Not SQ_OFFBOARD(t) AndAlso p.board(t) = king Then Return True
    Next

    '' Diagonal sliders (bishop, queen)
    Dim As Integer bishop = MAKE_PIECE(bySide, PT_BISHOP)
    Dim As Integer queen = MAKE_PIECE(bySide, PT_QUEEN)
    For i = 0 To 3
        d = BishopDirs(i)
        t = sq + d
        Do While Not SQ_OFFBOARD(t)
            pc = p.board(t)
            If pc <> PC_EMPTY Then
                If pc = bishop OrElse pc = queen Then Return True
                Exit Do
            End If
            t += d
        Loop
    Next

    '' Orthogonal sliders (rook, queen)
    Dim As Integer rook = MAKE_PIECE(bySide, PT_ROOK)
    For i = 0 To 3
        d = RookDirs(i)
        t = sq + d
        Do While Not SQ_OFFBOARD(t)
            pc = p.board(t)
            If pc <> PC_EMPTY Then
                If pc = rook OrElse pc = queen Then Return True
                Exit Do
            End If
            t += d
        Loop
    Next

    Return False
End Function

Function Pos_InCheck(ByRef p As Position) As Boolean
    Return Pos_IsSquareAttacked(p, p.kingSq(p.sideToMove), p.sideToMove Xor 1)
End Function

'' Number of enemy pieces giving check to the side to move (0, 1 or 2).
'' Used for teaching ("double check!") rather than by move generation.
Function Pos_CountCheckers(ByRef p As Position) As Integer
    Dim As Integer us = p.sideToMove, them = us Xor 1
    Dim As Integer ksq = p.kingSq(us)
    Dim As Integer count = 0, s
    '' Test each enemy piece individually to see whether it attacks the king.
    For s = 0 To 127
        If SQ_OFFBOARD(s) Then Continue For
        Dim As Integer pc = p.board(s)
        If pc = PC_EMPTY OrElse PIECE_COLOR(pc) <> them Then Continue For
        Dim As Integer diff = ksq - s, pt = PIECE_TYPE(pc), i, t, hit = 0
        Select Case pt
        Case PT_PAWN
            If them = SIDE_WHITE Then
                If diff = 15 OrElse diff = 17 Then hit = 1
            Else
                If diff = -15 OrElse diff = -17 Then hit = 1
            End If
        Case PT_KNIGHT
            For i = 0 To 7
                If diff = KnightOffsets(i) Then hit = 1
            Next
        Case PT_KING
            '' A king never gives check.
        Case Else
            Dim As Integer nDirs = 0, dirs(0 To 7)
            If pt = PT_BISHOP OrElse pt = PT_QUEEN Then
                For i = 0 To 3 : dirs(nDirs) = BishopDirs(i) : nDirs += 1 : Next
            End If
            If pt = PT_ROOK OrElse pt = PT_QUEEN Then
                For i = 0 To 3 : dirs(nDirs) = RookDirs(i) : nDirs += 1 : Next
            End If
            For i = 0 To nDirs - 1
                t = s + dirs(i)
                Do While Not SQ_OFFBOARD(t)
                    If t = ksq Then hit = 1 : Exit Do
                    If p.board(t) <> PC_EMPTY Then Exit Do
                    t += dirs(i)
                Loop
            Next
        End Select
        count += hit
    Next
    Return count
End Function

'' ---------------------------------------------------------------------
'' Move generation
'' ---------------------------------------------------------------------
Private Sub AddMove(ByRef list As MoveList, ByVal fromSq As Integer, ByVal toSq As Integer, _
                    ByVal piece As Integer, ByVal captured As Integer, _
                    ByVal promo As Integer, ByVal flags As Integer)
    If list.count >= MAX_MOVES Then Exit Sub
    With list.moves(list.count)
        .fromSq = fromSq
        .toSq = toSq
        .piece = piece
        .captured = captured
        .promotion = promo
        .flags = flags
    End With
    list.count += 1
End Sub

'' Adds a pawn move, expanding it into four moves when it promotes.
Private Sub AddPawnMove(ByRef list As MoveList, ByVal fromSq As Integer, ByVal toSq As Integer, _
                        ByVal piece As Integer, ByVal captured As Integer, ByVal flags As Integer)
    Dim As Integer r = SQ_RANK(toSq)
    If r = 7 OrElse r = 0 Then
        AddMove(list, fromSq, toSq, piece, captured, PT_QUEEN, flags Or MF_PROMOTION)
        AddMove(list, fromSq, toSq, piece, captured, PT_ROOK, flags Or MF_PROMOTION)
        AddMove(list, fromSq, toSq, piece, captured, PT_BISHOP, flags Or MF_PROMOTION)
        AddMove(list, fromSq, toSq, piece, captured, PT_KNIGHT, flags Or MF_PROMOTION)
    Else
        AddMove(list, fromSq, toSq, piece, captured, PT_NONE, flags)
    End If
End Sub

Sub Pos_GeneratePseudo(ByRef p As Position, ByRef list As MoveList)
    list.count = 0
    Dim As Integer us = p.sideToMove, them = us Xor 1
    Dim As Integer s, t, i, d, pc, target

    Dim As Integer pawnDir = IIf(us = SIDE_WHITE, 16, -16)
    Dim As Integer startRank = IIf(us = SIDE_WHITE, 1, 6)

    For s = 0 To 127
        If SQ_OFFBOARD(s) Then
            s += 7          '' jump to the start of the next real rank
            Continue For
        End If
        pc = p.board(s)
        If pc = PC_EMPTY OrElse PIECE_COLOR(pc) <> us Then Continue For

        Select Case PIECE_TYPE(pc)
        Case PT_PAWN
            '' Forward moves
            t = s + pawnDir
            If Not SQ_OFFBOARD(t) AndAlso p.board(t) = PC_EMPTY Then
                AddPawnMove(list, s, t, pc, PC_EMPTY, 0)
                If SQ_RANK(s) = startRank AndAlso p.board(t + pawnDir) = PC_EMPTY Then
                    AddMove(list, s, t + pawnDir, pc, PC_EMPTY, PT_NONE, MF_DOUBLE_PUSH)
                End If
            End If
            '' Captures (including en passant)
            For i = -1 To 1 Step 2
                t = s + pawnDir + i
                If SQ_OFFBOARD(t) Then Continue For
                target = p.board(t)
                If target <> PC_EMPTY Then
                    If PIECE_COLOR(target) = them Then AddPawnMove(list, s, t, pc, target, MF_CAPTURE)
                ElseIf t = p.epSquare Then
                    AddMove(list, s, t, pc, MAKE_PIECE(them, PT_PAWN), PT_NONE, MF_CAPTURE Or MF_EN_PASSANT)
                End If
            Next

        Case PT_KNIGHT
            For i = 0 To 7
                t = s + KnightOffsets(i)
                If SQ_OFFBOARD(t) Then Continue For
                target = p.board(t)
                If target = PC_EMPTY Then
                    AddMove(list, s, t, pc, PC_EMPTY, PT_NONE, 0)
                ElseIf PIECE_COLOR(target) = them Then
                    AddMove(list, s, t, pc, target, PT_NONE, MF_CAPTURE)
                End If
            Next

        Case PT_KING
            For i = 0 To 7
                t = s + KingOffsets(i)
                If SQ_OFFBOARD(t) Then Continue For
                target = p.board(t)
                If target = PC_EMPTY Then
                    AddMove(list, s, t, pc, PC_EMPTY, PT_NONE, 0)
                ElseIf PIECE_COLOR(target) = them Then
                    AddMove(list, s, t, pc, target, PT_NONE, MF_CAPTURE)
                End If
            Next

        Case Else
            '' Sliding pieces
            Dim As Integer pt = PIECE_TYPE(pc)
            Dim As Integer nDirs = 0, dirs(0 To 7)
            If pt = PT_BISHOP OrElse pt = PT_QUEEN Then
                For i = 0 To 3 : dirs(nDirs) = BishopDirs(i) : nDirs += 1 : Next
            End If
            If pt = PT_ROOK OrElse pt = PT_QUEEN Then
                For i = 0 To 3 : dirs(nDirs) = RookDirs(i) : nDirs += 1 : Next
            End If
            For i = 0 To nDirs - 1
                d = dirs(i)
                t = s + d
                Do While Not SQ_OFFBOARD(t)
                    target = p.board(t)
                    If target = PC_EMPTY Then
                        AddMove(list, s, t, pc, PC_EMPTY, PT_NONE, 0)
                    Else
                        If PIECE_COLOR(target) = them Then AddMove(list, s, t, pc, target, PT_NONE, MF_CAPTURE)
                        Exit Do
                    End If
                    t += d
                Loop
            Next
        End Select
    Next

    '' Castling. The king may not castle out of, through, or into check.
    '' "Into check" is caught by the legality filter like any other move.
    If us = SIDE_WHITE Then
        If (p.castling And (CR_WHITE_KING Or CR_WHITE_QUEEN)) <> 0 AndAlso p.board(SQ_E1) = PC_WK Then
            If (p.castling And CR_WHITE_KING) <> 0 AndAlso p.board(SQ_H1) = PC_WR AndAlso _
               p.board(SQ_F1) = PC_EMPTY AndAlso p.board(SQ_G1) = PC_EMPTY Then
                If Not Pos_IsSquareAttacked(p, SQ_E1, them) AndAlso _
                   Not Pos_IsSquareAttacked(p, SQ_F1, them) Then
                    AddMove(list, SQ_E1, SQ_G1, PC_WK, PC_EMPTY, PT_NONE, MF_CASTLE)
                End If
            End If
            If (p.castling And CR_WHITE_QUEEN) <> 0 AndAlso p.board(SQ_A1) = PC_WR AndAlso _
               p.board(SQ_D1) = PC_EMPTY AndAlso p.board(SQ_C1) = PC_EMPTY AndAlso _
               p.board(SQ_B1) = PC_EMPTY Then
                If Not Pos_IsSquareAttacked(p, SQ_E1, them) AndAlso _
                   Not Pos_IsSquareAttacked(p, SQ_D1, them) Then
                    AddMove(list, SQ_E1, SQ_C1, PC_WK, PC_EMPTY, PT_NONE, MF_CASTLE)
                End If
            End If
        End If
    Else
        If (p.castling And (CR_BLACK_KING Or CR_BLACK_QUEEN)) <> 0 AndAlso p.board(SQ_E8) = PC_BK Then
            If (p.castling And CR_BLACK_KING) <> 0 AndAlso p.board(SQ_H8) = PC_BR AndAlso _
               p.board(SQ_F8) = PC_EMPTY AndAlso p.board(SQ_G8) = PC_EMPTY Then
                If Not Pos_IsSquareAttacked(p, SQ_E8, them) AndAlso _
                   Not Pos_IsSquareAttacked(p, SQ_F8, them) Then
                    AddMove(list, SQ_E8, SQ_G8, PC_BK, PC_EMPTY, PT_NONE, MF_CASTLE)
                End If
            End If
            If (p.castling And CR_BLACK_QUEEN) <> 0 AndAlso p.board(SQ_A8) = PC_BR AndAlso _
               p.board(SQ_D8) = PC_EMPTY AndAlso p.board(SQ_C8) = PC_EMPTY AndAlso _
               p.board(SQ_B8) = PC_EMPTY Then
                If Not Pos_IsSquareAttacked(p, SQ_E8, them) AndAlso _
                   Not Pos_IsSquareAttacked(p, SQ_D8, them) Then
                    AddMove(list, SQ_E8, SQ_C8, PC_BK, PC_EMPTY, PT_NONE, MF_CASTLE)
                End If
            End If
        End If
    End If
End Sub

Sub Pos_GenerateLegal(ByRef p As Position, ByRef list As MoveList)
    Dim As MoveList pseudo
    Pos_GeneratePseudo(p, pseudo)
    list.count = 0
    Dim As Integer i
    For i = 0 To pseudo.count - 1
        If Pos_MakeMove(p, pseudo.moves(i)) Then
            If Not Pos_LastMoveWasIllegal(p) Then
                list.moves(list.count) = pseudo.moves(i)
                list.count += 1
            End If
            Pos_UnmakeMove(p)
        End If
    Next
End Sub

Function Pos_HasLegalMove(ByRef p As Position) As Boolean
    Dim As MoveList pseudo
    Pos_GeneratePseudo(p, pseudo)
    Dim As Integer i
    For i = 0 To pseudo.count - 1
        If Pos_MakeMove(p, pseudo.moves(i)) Then
            Dim As Boolean ok = Not Pos_LastMoveWasIllegal(p)
            Pos_UnmakeMove(p)
            If ok Then Return True
        End If
    Next
    Return False
End Function

Function Pos_FindLegalMove(ByRef p As Position, ByVal fromSq As Integer, _
                           ByVal toSq As Integer, ByVal promoType As Integer, _
                           ByRef outMove As ChessMove) As Boolean
    Dim As MoveList list
    Pos_GenerateLegal(p, list)
    Dim As Integer i
    For i = 0 To list.count - 1
        With list.moves(i)
            If .fromSq = fromSq AndAlso .toSq = toSq AndAlso .promotion = promoType Then
                outMove = list.moves(i)
                Return True
            End If
        End With
    Next
    Return False
End Function

'' ---------------------------------------------------------------------
'' Making and unmaking moves
'' ---------------------------------------------------------------------
Function Pos_MakeMove(ByRef p As Position, ByRef m As ChessMove) As Boolean
    If p.historyCount >= MAX_HISTORY Then Return False

    With p.undoStack(p.historyCount)
        .mv = m
        .castling = p.castling
        .epSquare = p.epSquare
        .halfmove = p.halfmoveClock
        .hash = p.hash
    End With
    p.historyCount += 1

    Dim As Integer us = p.sideToMove, them = us Xor 1
    Dim As Integer fromSq = m.fromSq, toSq = m.toSq
    Dim As Integer piece = m.piece
    Dim As ULongInt h = p.hash

    '' Remove the old en-passant square and castling rights from the hash.
    If EpIsHashable(p) Then h Xor= ZobEpFile(SQ_FILE(p.epSquare))
    p.epSquare = NO_SQUARE
    h Xor= ZobCastle(p.castling)

    '' Lift the moving piece.
    p.board(fromSq) = PC_EMPTY
    h Xor= ZobPiece(piece, fromSq)

    '' Remove a captured piece.
    If m.flags And MF_EN_PASSANT Then
        Dim As Integer capSq = IIf(us = SIDE_WHITE, toSq - 16, toSq + 16)
        p.board(capSq) = PC_EMPTY
        h Xor= ZobPiece(m.captured, capSq)
    ElseIf m.captured <> PC_EMPTY Then
        h Xor= ZobPiece(m.captured, toSq)
    End If

    '' Put the piece (or the promoted piece) down.
    Dim As Integer placed = piece
    If m.promotion <> PT_NONE Then placed = MAKE_PIECE(us, m.promotion)
    p.board(toSq) = placed
    h Xor= ZobPiece(placed, toSq)

    '' Castling also moves the rook.
    If m.flags And MF_CASTLE Then
        Dim As Integer rFrom, rTo
        If toSq > fromSq Then
            rFrom = toSq + 1 : rTo = toSq - 1      '' king side
        Else
            rFrom = toSq - 2 : rTo = toSq + 1      '' queen side
        End If
        Dim As Integer rook = p.board(rFrom)
        p.board(rFrom) = PC_EMPTY
        p.board(rTo) = rook
        h Xor= ZobPiece(rook, rFrom)
        h Xor= ZobPiece(rook, rTo)
    End If

    If PIECE_TYPE(piece) = PT_KING Then p.kingSq(us) = toSq

    p.castling = p.castling And CastleKeepMask(fromSq) And CastleKeepMask(toSq)
    h Xor= ZobCastle(p.castling)

    If PIECE_TYPE(piece) = PT_PAWN OrElse m.captured <> PC_EMPTY Then
        p.halfmoveClock = 0
    Else
        p.halfmoveClock += 1
    End If
    If us = SIDE_BLACK Then p.fullmoveNumber += 1

    p.sideToMove = them
    h Xor= ZobSide

    If m.flags And MF_DOUBLE_PUSH Then
        p.epSquare = (fromSq + toSq) \ 2
        If EpIsHashable(p) Then h Xor= ZobEpFile(SQ_FILE(p.epSquare))
    End If

    p.hash = h
    Return True
End Function

Function Pos_MakeNullMove(ByRef p As Position) As Boolean
    If p.historyCount >= MAX_HISTORY Then Return False
    With p.undoStack(p.historyCount)
        .mv.fromSq = 0 : .mv.toSq = 0 : .mv.piece = PC_EMPTY
        .mv.captured = PC_EMPTY : .mv.promotion = PT_NONE : .mv.flags = 0
        .castling = p.castling
        .epSquare = p.epSquare
        .halfmove = p.halfmoveClock
        .hash = p.hash
    End With
    p.historyCount += 1
    If EpIsHashable(p) Then p.hash Xor= ZobEpFile(SQ_FILE(p.epSquare))
    p.epSquare = NO_SQUARE
    p.sideToMove Xor= 1
    p.hash Xor= ZobSide
    '' Positions before a null move must not count as repetitions.
    p.halfmoveClock = 0
    Return True
End Function

Sub Pos_UnmakeMove(ByRef p As Position)
    If p.historyCount <= 0 Then Exit Sub
    p.historyCount -= 1

    Dim As UndoInfo Ptr u = @p.undoStack(p.historyCount)
    Dim As ChessMove m = u->mv
    If m.piece = PC_EMPTY Then
        '' Undo a null move.
        p.sideToMove Xor= 1
        p.castling = u->castling
        p.epSquare = u->epSquare
        p.halfmoveClock = u->halfmove
        p.hash = u->hash
        Exit Sub
    End If
    Dim As Integer them = p.sideToMove, us = them Xor 1
    p.sideToMove = us

    p.board(m.fromSq) = m.piece
    If m.flags And MF_EN_PASSANT Then
        p.board(m.toSq) = PC_EMPTY
        p.board(IIf(us = SIDE_WHITE, m.toSq - 16, m.toSq + 16)) = m.captured
    Else
        p.board(m.toSq) = m.captured
    End If

    If m.flags And MF_CASTLE Then
        Dim As Integer rFrom, rTo
        If m.toSq > m.fromSq Then
            rFrom = m.toSq + 1 : rTo = m.toSq - 1
        Else
            rFrom = m.toSq - 2 : rTo = m.toSq + 1
        End If
        p.board(rFrom) = p.board(rTo)
        p.board(rTo) = PC_EMPTY
    End If

    If PIECE_TYPE(m.piece) = PT_KING Then p.kingSq(us) = m.fromSq
    If us = SIDE_BLACK Then p.fullmoveNumber -= 1

    p.castling = u->castling
    p.epSquare = u->epSquare
    p.halfmoveClock = u->halfmove
    p.hash = u->hash
End Sub

Function Pos_LastMoveWasIllegal(ByRef p As Position) As Boolean
    Dim As Integer mover = p.sideToMove Xor 1
    Return Pos_IsSquareAttacked(p, p.kingSq(mover), p.sideToMove)
End Function

'' ---------------------------------------------------------------------
'' Draw rules
'' ---------------------------------------------------------------------
Function Pos_RepetitionCount(ByRef p As Position) As Integer
    Dim As Integer count = 1
    '' Only positions since the last capture or pawn move can repeat, and
    '' only those with the same side to move (every second ply).
    Dim As Integer oldest = p.historyCount - p.halfmoveClock
    If oldest < 0 Then oldest = 0
    Dim As Integer i = p.historyCount - 2
    Do While i >= oldest
        If p.undoStack(i).hash = p.hash Then count += 1
        i -= 2
    Loop
    Return count
End Function

'' True when neither side can possibly checkmate:
'' K v K, K+minor v K, or kings plus bishops that all stand on one colour.
Function Pos_IsInsufficientMaterial(ByRef p As Position) As Boolean
    Dim As Integer s, knights = 0, bishops = 0
    Dim As Integer bishopLight = 0, bishopDark = 0
    For s = 0 To 127
        If SQ_OFFBOARD(s) Then Continue For
        Dim As Integer pc = p.board(s)
        Select Case PIECE_TYPE(pc)
        Case PT_PAWN, PT_ROOK, PT_QUEEN
            Return False
        Case PT_KNIGHT
            knights += 1
        Case PT_BISHOP
            bishops += 1
            If ((SQ_FILE(s) + SQ_RANK(s)) And 1) = 1 Then bishopLight += 1 Else bishopDark += 1
        End Select
    Next
    If knights = 0 AndAlso bishops = 0 Then Return True
    If knights + bishops = 1 Then Return True
    If knights = 0 AndAlso (bishopLight = 0 OrElse bishopDark = 0) Then Return True
    Return False
End Function

'' ---------------------------------------------------------------------
'' Perft: counts leaf nodes of the legal move tree. Used to verify the
'' move generator against published reference numbers.
'' ---------------------------------------------------------------------
Function Pos_Perft(ByRef p As Position, ByVal depth As Integer) As ULongInt
    If depth <= 0 Then Return 1
    Dim As MoveList list
    Pos_GeneratePseudo(p, list)
    Dim As ULongInt nodes = 0
    Dim As Integer i
    For i = 0 To list.count - 1
        If Pos_MakeMove(p, list.moves(i)) Then
            If Not Pos_LastMoveWasIllegal(p) Then
                If depth = 1 Then nodes += 1 Else nodes += Pos_Perft(p, depth - 1)
            End If
            Pos_UnmakeMove(p)
        End If
    Next
    Return nodes
End Function
