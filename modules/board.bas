'' =====================================================================
'' BeginnerChess - board.bas
'' Board rendering. See board.bi.
'' =====================================================================
#include once "board.bi"

Type ThemeColors
    light   As ULong
    dark    As ULong
    frame1  As ULong      '' frame gradient top
    frame2  As ULong      '' frame gradient bottom
    coord   As ULong      '' coordinate text
    lastMv  As ULong      '' last-move tint
    selectC As ULong      '' selected square tint
    dotC    As ULong      '' legal-move dots / capture rings
    hoverC  As ULong
End Type

Private Function GetTheme(ByVal t As Integer) As ThemeColors
    Dim As ThemeColors c
    c.coord = RGB(240, 228, 205)
    c.lastMv = RGBA(255, 220, 50, 105)
    c.selectC = RGBA(60, 190, 80, 130)
    c.dotC = RGBA(25, 45, 25, 80)
    c.hoverC = RGBA(255, 255, 255, 70)
    Select Case t
    Case THEME_WOOD
        c.light = RGB(228, 192, 142) : c.dark = RGB(146, 94, 56)
        c.frame1 = RGB(96, 58, 30) : c.frame2 = RGB(62, 36, 18)
    Case THEME_MARBLE
        c.light = RGB(236, 236, 230) : c.dark = RGB(122, 134, 148)
        c.frame1 = RGB(88, 94, 104) : c.frame2 = RGB(52, 56, 64)
    Case THEME_SIMPLE
        c.light = RGB(238, 238, 214) : c.dark = RGB(118, 150, 86)
        c.frame1 = RGB(72, 92, 58) : c.frame2 = RGB(46, 60, 36)
    Case THEME_CONTRAST
        c.light = RGB(255, 255, 255) : c.dark = RGB(48, 58, 140)
        c.frame1 = RGB(16, 16, 16) : c.frame2 = RGB(0, 0, 0)
        c.coord = RGB(255, 230, 0)
        c.lastMv = RGBA(255, 200, 0, 150)
        c.selectC = RGBA(0, 220, 60, 170)
        c.dotC = RGBA(230, 30, 30, 170)
        c.hoverC = RGBA(255, 160, 0, 120)
    Case Else   '' THEME_CLASSIC
        c.light = RGB(240, 217, 181) : c.dark = RGB(181, 136, 99)
        c.frame1 = RGB(110, 74, 44) : c.frame2 = RGB(74, 48, 26)
    End Select
    Return c
End Function

Function Board_ThemeName(ByVal theme As Integer) As String
    Select Case theme
    Case THEME_CLASSIC  : Return "Classic"
    Case THEME_WOOD     : Return "Wood"
    Case THEME_MARBLE   : Return "Marble"
    Case THEME_SIMPLE   : Return "Simple"
    Case THEME_CONTRAST : Return "High Contrast"
    End Select
    Return "?"
End Function

Sub Board_ClearMarks(ByRef mk As BoardMarks)
    mk.selectedSq = NO_SQUARE
    mk.lastFrom = NO_SQUARE
    mk.lastTo = NO_SQUARE
    mk.checkSq = NO_SQUARE
    mk.hoverSq = NO_SQUARE
    mk.errorSq = NO_SQUARE
    mk.errorAlpha = 0
    mk.hintFrom = NO_SQUARE
    mk.hintTo = NO_SQUARE
    mk.hideSq = NO_SQUARE
    mk.hideSq2 = NO_SQUARE
    Dim As Integer i
    For i = 0 To 127
        mk.targets(i) = 0
        mk.highlight(i) = 0
    Next
    mk.arrowCount = 0
End Sub

Sub Board_AddArrow(ByRef mk As BoardMarks, ByVal fromSq As Integer, ByVal toSq As Integer, ByVal colorId As Integer)
    If mk.arrowCount > 15 OrElse fromSq = NO_SQUARE OrElse toSq = NO_SQUARE Then Exit Sub
    mk.arrowFrom(mk.arrowCount) = fromSq
    mk.arrowTo(mk.arrowCount) = toSq
    mk.arrowColor(mk.arrowCount) = colorId
    mk.arrowCount += 1
End Sub

Private Function MarkColor(ByVal id As Integer, ByVal alpha As Integer) As ULong
    Select Case id
    Case MARK_RED    : Return RGBA(220, 50, 40, alpha)
    Case MARK_BLUE   : Return RGBA(40, 110, 230, alpha)
    Case MARK_YELLOW : Return RGBA(240, 190, 20, alpha)
    End Select
    Return RGBA(40, 170, 60, alpha)
End Function

Sub Board_Layout(ByRef bv As BoardView, ByVal x As Integer, ByVal y As Integer, ByVal sqSize As Integer)
    bv.sqSize = sqSize
    If bv.showCoords Then
        bv.margin = sqSize * 0.32
        If bv.margin < 20 Then bv.margin = 20
    Else
        bv.margin = sqSize * 0.12
        If bv.margin < 8 Then bv.margin = 8
    End If
    bv.x = x + bv.margin
    bv.y = y + bv.margin
End Sub

Function Board_OuterSize(ByRef bv As BoardView) As Integer
    Return bv.sqSize * 8 + bv.margin * 2
End Function

'' ---------------------------------------------------------------------
'' Procedural textures (value noise)
'' ---------------------------------------------------------------------
Private Function Hash2(ByVal ix As Integer, ByVal iy As Integer, ByVal seed As Integer) As Single
    Dim As ULong h = CULng(ix) * 374761393UL + CULng(iy) * 668265263UL + CULng(seed) * 2246822519UL
    h = (h Xor (h Shr 13)) * 1274126177UL
    h = h Xor (h Shr 16)
    Return (h And &hFFFFFF) / 16777216.0
End Function

Private Function ValueNoise(ByVal x As Single, ByVal y As Single, ByVal seed As Integer) As Single
    Dim As Integer ix = Int(x), iy = Int(y)
    Dim As Single fx = x - ix, fy = y - iy
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    Dim As Single a = Hash2(ix, iy, seed), b = Hash2(ix + 1, iy, seed)
    Dim As Single c = Hash2(ix, iy + 1, seed), d = Hash2(ix + 1, iy + 1, seed)
    Return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy
End Function

Private Function Fbm(ByVal x As Single, ByVal y As Single, ByVal seed As Integer) As Single
    Return ValueNoise(x, y, seed) * 0.57 + ValueNoise(x * 2.1, y * 2.1, seed + 7) * 0.29 + _
           ValueNoise(x * 4.3, y * 4.3, seed + 13) * 0.14
End Function

'' Colour of one pixel of a textured square. (u, v) = pixel inside the
'' square, (gx, gy) = pixel on the whole board, isLight = square colour.
Private Function TexturePixel(ByVal theme As Integer, ByVal baseColor As ULong, ByVal u As Integer, ByVal v As Integer, _
                              ByVal gx As Integer, ByVal gy As Integer, ByVal sqIndex As Integer, _
                              ByVal sqSize As Integer) As ULong
    Dim As Single k = 80.0 / sqSize          '' keep texture scale stable across sizes
    Select Case theme
    Case THEME_WOOD
        Dim As Single along, across
        If (sqIndex And 1) = 0 Then
            along = u * k : across = v * k
        Else
            along = v * k : across = u * k
        End If
        Dim As Single n = Fbm(along * 0.025, across * 0.11 + sqIndex * 3.7, 11)
        Dim As Single rings = Sin(across * 0.32 + n * 9.0 + sqIndex)
        Dim As Single fine = ValueNoise(along * 0.5, across * 2.5, sqIndex + 50)
        Dim As Single tone = 0.9 + rings * 0.07 + (fine - 0.5) * 0.08
        Return Color_Shade(baseColor, tone)
    Case THEME_MARBLE
        Dim As Single x = gx * k, y = gy * k
        '' Turbulence (sum of absolute noise) bends straight stripes into veins.
        Dim As Single turb = Abs(ValueNoise(x * 0.010, y * 0.010, 5) - 0.5) * 1.0 + _
                             Abs(ValueNoise(x * 0.022, y * 0.022, 6) - 0.5) * 0.5 + _
                             Abs(ValueNoise(x * 0.050, y * 0.050, 7) - 0.5) * 0.25
        Dim As Single vein = Abs(Sin((x * 0.7 + y) * 0.012 + turb * 9.0))
        vein = vein ^ 0.35
        Dim As Single cloud = Fbm(x * 0.03, y * 0.03, 9)
        Dim As Single tone = 0.83 + 0.17 * vein + (cloud - 0.5) * 0.10
        Return Color_Shade(baseColor, tone)
    Case THEME_CLASSIC
        '' Very faint grain so the board does not look flat.
        Dim As Single tone = 0.985 + (ValueNoise(u * k * 0.3, v * k * 1.2, sqIndex) - 0.5) * 0.04
        Return Color_Shade(baseColor, tone)
    End Select
    Return baseColor
End Function

Private Sub BuildBoardImage(ByRef bv As BoardView)
    If bv.boardImg Then ImageDestroy bv.boardImg : bv.boardImg = 0
    Dim As ThemeColors tc = GetTheme(bv.theme)
    Dim As Integer outer = Board_OuterSize(bv), sq = bv.sqSize, m = bv.margin
    bv.boardImg = ImageCreate(outer, outer, RGBA(0, 0, 0, 0), 32)

    '' Frame: rounded, with a vertical gradient and a thin inner bevel.
    Dim As Integer i
    For i = 0 To outer - 1
        Dim As ULong fc = Color_Mix(tc.frame1, tc.frame2, i / outer)
        Line bv.boardImg, (0, i)-(outer - 1, i), fc
    Next
    '' Round the outer corners by clearing them.
    Dim As Integer r = 8, cx, cy
    For cy = 0 To r - 1
        For cx = 0 To r - 1
            Dim As Single dx = r - cx - 0.5, dy = r - cy - 0.5
            If dx * dx + dy * dy > r * r Then
                PSet bv.boardImg, (cx, cy), RGBA(0, 0, 0, 0)
                PSet bv.boardImg, (outer - 1 - cx, cy), RGBA(0, 0, 0, 0)
                PSet bv.boardImg, (cx, outer - 1 - cy), RGBA(0, 0, 0, 0)
                PSet bv.boardImg, (outer - 1 - cx, outer - 1 - cy), RGBA(0, 0, 0, 0)
            End If
        Next
    Next
    Line bv.boardImg, (m - 2, m - 2)-(m + 8 * sq + 1, m + 8 * sq + 1), RGBA(0, 0, 0, 255), B
    Line bv.boardImg, (m - 1, m - 1)-(m + 8 * sq, m + 8 * sq), Color_Shade(tc.frame1, 1.5), B

    '' Squares (row 0 = top of the screen = rank 8 when not flipped;
    '' the light/dark pattern is the same either way).
    Dim As Any Ptr pixAny
    Dim As Long pitch
    ImageInfo bv.boardImg, , , , pitch, pixAny
    Dim As Integer row, col, u, v
    For row = 0 To 7
        For col = 0 To 7
            Dim As Boolean isLight = ((row + col) And 1) = 0
            Dim As ULong baseColor = IIf(isLight, tc.light, tc.dark)
            Dim As Integer sqIndex = row * 8 + col
            For v = 0 To sq - 1
                Dim As ULong Ptr rowPtr = Cast(ULong Ptr, Cast(UByte Ptr, pixAny) + (m + row * sq + v) * pitch)
                For u = 0 To sq - 1
                    Dim As Integer gx = col * sq + u, gy = row * sq + v
                    rowPtr[m + gx] = TexturePixel(bv.theme, baseColor, u, v, gx, gy, sqIndex, sq) Or &hFF000000UL
                Next
            Next
        Next
    Next

    bv.builtSize = sq
    bv.builtTheme = bv.theme
End Sub

Private Sub EnsureBuilt(ByRef bv As BoardView)
    Dim As Boolean stale = (bv.boardImg = 0) OrElse (bv.builtSize <> bv.sqSize) OrElse (bv.builtTheme <> bv.theme)
    If bv.builtCoords <> bv.showCoords Then stale = True
    If stale Then
        BuildBoardImage(bv)
        bv.builtCoords = bv.showCoords
    End If
    If bv.pieces.size <> bv.sqSize OrElse bv.pieces.style <> bv.pieceSet Then Pieces_Build(bv.pieces, bv.sqSize, bv.pieceSet)
End Sub

Sub Board_Free(ByRef bv As BoardView)
    If bv.boardImg Then ImageDestroy bv.boardImg : bv.boardImg = 0
    Pieces_Free(bv.pieces)
End Sub

'' ---------------------------------------------------------------------
'' Coordinates
'' ---------------------------------------------------------------------
Function Board_SquareAt(ByRef bv As BoardView, ByVal mx As Integer, ByVal my As Integer) As Integer
    If mx < bv.x OrElse my < bv.y Then Return NO_SQUARE
    Dim As Integer col = (mx - bv.x) \ bv.sqSize, row = (my - bv.y) \ bv.sqSize
    If col > 7 OrElse row > 7 Then Return NO_SQUARE
    Dim As Integer file = IIf(bv.flipped, 7 - col, col)
    Dim As Integer rank = IIf(bv.flipped, row, 7 - row)
    Return MAKE_SQ(file, rank)
End Function

Sub Board_SquareXY(ByRef bv As BoardView, ByVal sq As Integer, ByRef px As Integer, ByRef py As Integer)
    Dim As Integer file = SQ_FILE(sq), rank = SQ_RANK(sq)
    Dim As Integer col = IIf(bv.flipped, 7 - file, file)
    Dim As Integer row = IIf(bv.flipped, rank, 7 - rank)
    px = bv.x + col * bv.sqSize
    py = bv.y + row * bv.sqSize
End Sub

Sub Board_DrawPiece(ByRef bv As BoardView, ByVal pc As Integer, ByVal px As Integer, ByVal py As Integer)
    If bv.pieces.size <> bv.sqSize OrElse bv.pieces.style <> bv.pieceSet Then Pieces_Build(bv.pieces, bv.sqSize, bv.pieceSet)
    Pieces_Draw(bv.pieces, pc, px, py)
End Sub

'' ---------------------------------------------------------------------
'' Drawing
'' ---------------------------------------------------------------------
Sub Board_Draw(ByRef bv As BoardView, ByRef p As Position, ByRef mk As BoardMarks)
    EnsureBuilt(bv)
    Dim As ThemeColors tc = GetTheme(bv.theme)
    Dim As Integer sq = bv.sqSize, m = bv.margin, i, px, py

    '' Soft shadow, then the pre-rendered board.
    Gfx_RoundRect(bv.x - m + 3, bv.y - m + 6, 8 * sq + 2 * m, 8 * sq + 2 * m, 10, RGBA(0, 0, 0, 70))
    Put (bv.x - m, bv.y - m), bv.boardImg, Alpha

    '' Coordinates in the frame.
    If bv.showCoords Then
        Dim As Integer ts = m * 0.7
        If ts > 22 Then ts = 22
        If ts < 12 Then ts = 12
        For i = 0 To 7
            Dim As String fileCh = Chr(Asc("a") + IIf(bv.flipped, 7 - i, i))
            Dim As String rankCh = Chr(Asc("8") - IIf(bv.flipped, 7 - i, i))
            Text_DrawCentered(bv.x + i * sq + sq \ 2, bv.y + 8 * sq + (m - ts) \ 2, fileCh, ts, tc.coord)
            Text_DrawCentered(bv.x - m \ 2, bv.y + i * sq + (sq - ts) \ 2, rankCh, ts, tc.coord)
        Next
    End If

    '' Square tints.
    #macro TINT(s, c)
        If (s) <> NO_SQUARE Then
            Board_SquareXY(bv, (s), px, py)
            Gfx_FillRect(px, py, sq, sq, (c))
        End If
    #endmacro
    TINT(mk.lastFrom, tc.lastMv)
    TINT(mk.lastTo, tc.lastMv)
    TINT(mk.hintFrom, RGBA(60, 140, 255, 110))
    TINT(mk.hintTo, RGBA(60, 140, 255, 110))
    TINT(mk.selectedSq, tc.selectC)
    TINT(mk.hoverSq, tc.hoverC)
    If mk.errorSq <> NO_SQUARE AndAlso mk.errorAlpha > 0 Then
        TINT(mk.errorSq, RGBA(230, 40, 40, mk.errorAlpha))
    End If

    '' Teaching highlights
    Dim As Integer hs
    For hs = 0 To 127
        If SQ_OFFBOARD(hs) OrElse mk.highlight(hs) = 0 Then Continue For
        Board_SquareXY(bv, hs, px, py)
        Gfx_FillRect(px, py, sq, sq, MarkColor(mk.highlight(hs), 95))
        Gfx_FillRect(px, py, sq, 3, MarkColor(mk.highlight(hs), 200))
        Gfx_FillRect(px, py + sq - 3, sq, 3, MarkColor(mk.highlight(hs), 200))
        Gfx_FillRect(px, py, 3, sq, MarkColor(mk.highlight(hs), 200))
        Gfx_FillRect(px + sq - 3, py, 3, sq, MarkColor(mk.highlight(hs), 200))
    Next

    '' King in check: red glow.
    If mk.checkSq <> NO_SQUARE Then
        Board_SquareXY(bv, mk.checkSq, px, py)
        Dim As Integer k
        For k = 0 To 5
            Gfx_FillCircle(px + sq / 2, py + sq / 2, sq * (0.62 - k * 0.07), RGBA(235, 30, 30, 34 + k * 8))
        Next
    End If

    '' Pieces.
    Dim As Integer s
    For s = 0 To 127
        If SQ_OFFBOARD(s) Then Continue For
        If p.board(s) = PC_EMPTY OrElse s = mk.hideSq OrElse s = mk.hideSq2 Then Continue For
        Board_SquareXY(bv, s, px, py)
        Pieces_Draw(bv.pieces, p.board(s), px, py)
    Next

    '' Arrows
    Dim As Integer ai
    For ai = 0 To mk.arrowCount - 1
        Dim As Integer x1, y1, x2, y2
        Board_SquareXY(bv, mk.arrowFrom(ai), x1, y1)
        Board_SquareXY(bv, mk.arrowTo(ai), x2, y2)
        Dim As Single cx1 = x1 + sq / 2, cy1 = y1 + sq / 2, cx2 = x2 + sq / 2, cy2 = y2 + sq / 2
        '' Stop the arrow a little before the centre of the target square.
        Dim As Single ddx = cx2 - cx1, ddy = cy2 - cy1, dl = Sqr(ddx * ddx + ddy * ddy)
        If dl > 1 Then
            cx2 -= ddx / dl * sq * 0.22
            cy2 -= ddy / dl * sq * 0.22
            cx1 += ddx / dl * sq * 0.18
            cy1 += ddy / dl * sq * 0.18
        End If
        Gfx_Arrow(cx1, cy1, cx2, cy2, sq * 0.16, MarkColor(mk.arrowColor(ai), 170))
    Next

    '' Legal-move markers on top of everything.
    For s = 0 To 127
        If SQ_OFFBOARD(s) OrElse mk.targets(s) = 0 Then Continue For
        Board_SquareXY(bv, s, px, py)
        If mk.targets(s) = 2 Then
            Gfx_Ring(px + sq / 2, py + sq / 2, sq * 0.48, sq * 0.09, tc.dotC)
        Else
            Gfx_FillCircle(px + sq / 2, py + sq / 2, sq * 0.15, tc.dotC)
        End If
    Next
End Sub
