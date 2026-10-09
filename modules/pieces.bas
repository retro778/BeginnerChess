'' =====================================================================
'' BeginnerChess - pieces.bas
'' Original vector chess pieces ("Classic" set), rasterised with 4x4
'' super-sampling for smooth edges. Copyright: part of BeginnerChess (MIT).
''
'' Each piece is described in a 100 x 100 design grid by a small shape
'' language (one shape per string element):
''   R x1,y1 x2,y2 r          filled rounded rectangle
''   E cx,cy rx,ry            filled ellipse
''   P x,y x,y ~cx,cy x,y ... filled polygon; "~" marks a quadratic curve
''                            control point between two points
''   L x,y ~cx,cy x,y ... w   detail line of width w (drawn on top)
''   D cx,cy r                detail dot
'' Filled shapes are painted in order; each gets a dark outline, so a
'' later shape (e.g. a collar) is visibly separated from earlier ones.
'' =====================================================================
#include once "pieces.bi"

Const MAX_PTS = 160
Const MAX_PRIMS = 16

Enum PrimKind
    PK_POLY = 1
    PK_ELLIPSE
    PK_LINE
    PK_DOT
End Enum

Type PiecePrim
    kind As Integer
    n    As Integer
    px(0 To MAX_PTS - 1) As Single
    py(0 To MAX_PTS - 1) As Single
    As Single cx, cy, rx, ry
    w  As Single
    As Single minX, minY, maxX, maxY
End Type

Type PieceShape
    count As Integer
    prims(0 To MAX_PRIMS - 1) As PiecePrim
End Type

Dim Shared Shapes(PT_PAWN To PT_KING) As PieceShape
Dim Shared ShapesReady As Boolean = False

'' ---------------------------------------------------------------------
'' Piece designs
'' ---------------------------------------------------------------------
Private Function DesignOf(ByVal pt As Integer) As String
    Select Case pt
    Case PT_PAWN
        Return "R 24,81 76,90 3;" & _
               "P 30,82 ~33,64 43,58 57,58 ~67,64 70,82;" & _
               "E 50,56 15,4.5;" & _
               "E 50,39 13,13"
    Case PT_ROOK
        Return "R 21,82 79,90 3;" & _
               "R 26,75 74,83 2;" & _
               "P 31,76 69,76 66,40 34,40;" & _
               "P 27,41 73,41 73,19 64,19 64,26 55,26 55,19 45,19 45,26 36,26 36,19 27,19;" & _
               "L 33,47 67,47 2;" & _
               "L 31,69 69,69 2"
    Case PT_KNIGHT
        Return "R 22,82 78,90 3;" & _
               "P 73,83 ~79,52 63,32 ~57,21 47,18 44,9 38,18 ~27,24 21,40 16,51 ~16,59 24,60 ~32,58 41,51 ~43,57 37,63 ~29,72 29,83;" & _
               "D 35,32 3;" & _
               "D 21,53 1.6;" & _
               "L 51,21 ~66,31 69,60 2.2"
    Case PT_BISHOP
        Return "R 22,82 78,90 3;" & _
               "P 31,83 ~36,68 42,63 58,63 ~64,68 69,83;" & _
               "E 50,61 15,4.5;" & _
               "P 37,58 ~23,42 50,19 ~77,42 63,58;" & _
               "E 50,15 5.5,5.5;" & _
               "L 55,31 46,44 3"
    Case PT_QUEEN
        Return "R 20,82 80,90 3;" & _
               "P 29,83 ~35,64 38,58 62,58 ~65,64 71,83;" & _
               "E 50,57 16,4.5;" & _
               "P 35,54 20,27 35,42 36,19 45,40 50,15 55,40 64,19 65,42 80,27 65,54;" & _
               "E 50,53 15,3.5;" & _
               "E 20,26 4.5,4.5;" & _
               "E 36,18 4.5,4.5;" & _
               "E 50,13 4.5,4.5;" & _
               "E 64,18 4.5,4.5;" & _
               "E 80,26 4.5,4.5"
    Case PT_KING
        Return "R 20,82 80,90 3;" & _
               "P 30,83 ~35,64 39,58 61,58 ~65,64 70,83;" & _
               "E 50,57 17,4.5;" & _
               "P 35,54 ~22,40 29,32 ~38,25 50,36 ~62,25 71,32 ~78,40 65,54;" & _
               "P 47,8 53,8 53,14 59,14 59,20 53,20 53,38 47,38 47,20 41,20 41,14 47,14"
    End Select
    Return ""
End Function

'' ---------------------------------------------------------------------
'' Parsing
'' ---------------------------------------------------------------------
Private Sub ParsePair(ByRef tok As Const String, ByRef x As Single, ByRef y As Single)
    Dim As Integer c = InStr(tok, ",")
    x = Val(Left(tok, c - 1))
    y = Val(Mid(tok, c + 1))
End Sub

Private Sub AddPoint(ByRef pr As PiecePrim, ByVal x As Single, ByVal y As Single)
    If pr.n >= MAX_PTS Then Exit Sub
    pr.px(pr.n) = x
    pr.py(pr.n) = y
    pr.n += 1
End Sub

'' Parses a list of points (with optional ~control points) from tokens.
Private Sub ParsePoints(toks() As String, ByVal first As Integer, ByVal last As Integer, ByRef pr As PiecePrim)
    Dim As Integer i = first
    Dim As Boolean haveCtrl = False
    Dim As Single ctlX, ctlY
    Do While i <= last
        Dim As String t = toks(i)
        Dim As Single x, y
        If Left(t, 1) = "~" Then
            ParsePair(Mid(t, 2), ctlX, ctlY)
            haveCtrl = True
        Else
            ParsePair(t, x, y)
            If haveCtrl AndAlso pr.n > 0 Then
                '' Quadratic Bezier from the previous point through the control point.
                Dim As Single x0 = pr.px(pr.n - 1), y0 = pr.py(pr.n - 1)
                Dim As Integer k
                For k = 1 To 12
                    Dim As Single t1 = k / 12, u = 1 - t1
                    AddPoint(pr, u * u * x0 + 2 * u * t1 * ctlX + t1 * t1 * x, _
                                 u * u * y0 + 2 * u * t1 * ctlY + t1 * t1 * y)
                Next
            Else
                AddPoint(pr, x, y)
            End If
            haveCtrl = False
        End If
        i += 1
    Loop
End Sub

Private Sub ComputeBounds(ByRef pr As PiecePrim)
    Dim As Integer i
    Select Case pr.kind
    Case PK_ELLIPSE
        pr.minX = pr.cx - pr.rx : pr.maxX = pr.cx + pr.rx
        pr.minY = pr.cy - pr.ry : pr.maxY = pr.cy + pr.ry
    Case PK_DOT
        pr.minX = pr.cx - pr.rx : pr.maxX = pr.cx + pr.rx
        pr.minY = pr.cy - pr.rx : pr.maxY = pr.cy + pr.rx
    Case Else
        pr.minX = 1e9 : pr.minY = 1e9 : pr.maxX = -1e9 : pr.maxY = -1e9
        For i = 0 To pr.n - 1
            If pr.px(i) < pr.minX Then pr.minX = pr.px(i)
            If pr.px(i) > pr.maxX Then pr.maxX = pr.px(i)
            If pr.py(i) < pr.minY Then pr.minY = pr.py(i)
            If pr.py(i) > pr.maxY Then pr.maxY = pr.py(i)
        Next
        If pr.kind = PK_LINE Then
            pr.minX -= pr.w : pr.minY -= pr.w : pr.maxX += pr.w : pr.maxY += pr.w
        End If
    End Select
End Sub

Private Sub ParseShape(ByRef design As Const String, ByRef shp As PieceShape)
    shp.count = 0
    Dim As String rest = design & ";"
    Do While Len(rest) > 0
        Dim As Integer sc = InStr(rest, ";")
        Dim As String part = Trim(Left(rest, sc - 1))
        rest = Mid(rest, sc + 1)
        If part = "" OrElse shp.count >= MAX_PRIMS Then Continue Do

        '' Tokenise on spaces.
        Dim As String toks(0 To 63)
        Dim As Integer nt = 0
        Dim As String cur = ""
        Dim As Integer i
        For i = 1 To Len(part) + 1
            Dim As String c = IIf(i <= Len(part), Mid(part, i, 1), " ")
            If c = " " Then
                If cur <> "" AndAlso nt <= 63 Then toks(nt) = cur : nt += 1
                cur = ""
            Else
                cur &= c
            End If
        Next

        Dim As PiecePrim Ptr pr = @shp.prims(shp.count)
        pr->n = 0
        Select Case toks(0)
        Case "R"
            Dim As Single x1, y1, x2, y2, r = Val(toks(3))
            ParsePair(toks(1), x1, y1)
            ParsePair(toks(2), x2, y2)
            pr->kind = PK_POLY
            '' Rounded rectangle as a polygon with quarter-circle corners.
            Dim As Integer corner, k
            Dim As Single ccx(0 To 3) = {x2 - r, x1 + r, x1 + r, x2 - r}
            Dim As Single ccy(0 To 3) = {y2 - r, y2 - r, y1 + r, y1 + r}
            For corner = 0 To 3
                For k = 0 To 6
                    Dim As Single ang = (corner * 90 + k * 15) * 3.14159265 / 180
                    AddPoint(*pr, ccx(corner) + r * Cos(ang), ccy(corner) + r * Sin(ang))
                Next
            Next
        Case "E"
            pr->kind = PK_ELLIPSE
            ParsePair(toks(1), pr->cx, pr->cy)
            ParsePair(toks(2), pr->rx, pr->ry)
        Case "P"
            pr->kind = PK_POLY
            ParsePoints(toks(), 1, nt - 1, *pr)
        Case "L"
            pr->kind = PK_LINE
            pr->w = Val(toks(nt - 1))
            ParsePoints(toks(), 1, nt - 2, *pr)
        Case "D"
            pr->kind = PK_DOT
            ParsePair(toks(1), pr->cx, pr->cy)
            pr->rx = Val(toks(2))
        Case Else
            Continue Do
        End Select
        ComputeBounds(*pr)
        shp.count += 1
    Loop
End Sub

Private Sub InitShapes()
    If ShapesReady Then Exit Sub
    Dim As Integer pt
    For pt = PT_PAWN To PT_KING
        ParseShape(DesignOf(pt), Shapes(pt))
    Next
    ShapesReady = True
End Sub

'' ---------------------------------------------------------------------
'' Geometry
'' ---------------------------------------------------------------------
Private Function SegDist(ByVal x As Single, ByVal y As Single, ByVal ax As Single, ByVal ay As Single, _
                         ByVal bx As Single, ByVal by As Single) As Single
    Dim As Single dx = bx - ax, dy = by - ay
    Dim As Single L2 = dx * dx + dy * dy
    Dim As Single t = 0
    If L2 > 0 Then t = ((x - ax) * dx + (y - ay) * dy) / L2
    If t < 0 Then t = 0
    If t > 1 Then t = 1
    Dim As Single qx = ax + t * dx - x, qy = ay + t * dy - y
    Return Sqr(qx * qx + qy * qy)
End Function

Private Function PolyInside(ByRef pr As PiecePrim, ByVal x As Single, ByVal y As Single) As Boolean
    Dim As Boolean inside = False
    Dim As Integer i, j = pr.n - 1
    For i = 0 To pr.n - 1
        If (pr.py(i) > y) <> (pr.py(j) > y) Then
            Dim As Single xc = pr.px(i) + (y - pr.py(i)) * (pr.px(j) - pr.px(i)) / (pr.py(j) - pr.py(i))
            If x < xc Then inside = Not inside
        End If
        j = i
    Next
    Return inside
End Function

Private Function PolyEdgeDist(ByRef pr As PiecePrim, ByVal x As Single, ByVal y As Single, _
                              ByVal closed As Boolean) As Single
    Dim As Single best = 1e9
    Dim As Integer i
    For i = 0 To pr.n - 2
        Dim As Single d = SegDist(x, y, pr.px(i), pr.py(i), pr.px(i + 1), pr.py(i + 1))
        If d < best Then best = d
    Next
    If closed AndAlso pr.n > 2 Then
        Dim As Single d = SegDist(x, y, pr.px(pr.n - 1), pr.py(pr.n - 1), pr.px(0), pr.py(0))
        If d < best Then best = d
    End If
    Return best
End Function

'' Returns the approximate distance inside the ellipse boundary (< 0 = outside).
Private Function EllipseDepth(ByRef pr As PiecePrim, ByVal x As Single, ByVal y As Single) As Single
    Dim As Single dx = x - pr.cx, dy = y - pr.cy
    Dim As Single f = (dx * dx) / (pr.rx * pr.rx) + (dy * dy) / (pr.ry * pr.ry) - 1
    Dim As Single gx = 2 * dx / (pr.rx * pr.rx), gy = 2 * dy / (pr.ry * pr.ry)
    Dim As Single g = Sqr(gx * gx + gy * gy)
    If g < 0.0001 Then Return pr.rx
    Return -f / g
End Function

'' ---------------------------------------------------------------------
'' Rendering
'' ---------------------------------------------------------------------
Sub Pieces_Free(ByRef set As PieceImages)
    Dim As Integer i
    For i = 0 To 15
        If set.img(i) Then ImageDestroy set.img(i) : set.img(i) = 0
    Next
    set.size = 0
End Sub

Function Pieces_SetName(ByVal style As Integer) As String
    If style = PIECESET_BOLD Then Return "Bold"
    Return "Classic"
End Function

Sub Pieces_Build(ByRef set As PieceImages, ByVal size As Integer, ByVal style As Integer = PIECESET_CLASSIC)
    InitShapes()
    Pieces_Free(set)
    set.size = size
    set.style = style
    If size < 8 Then size = 8

    Const SS = 4                                       '' samples per axis
    Dim As Single unitsPerPx = 100 / size
    '' Outline width in design units: about 2.4 px at 80 px, never under 1.2 px.
    Dim As Single strokeW = IIf(style = PIECESET_BOLD, 4.8, 3.0)
    If strokeW < 1.2 * unitsPerPx Then strokeW = 1.2 * unitsPerPx
    Dim As Single detailBoost = 0
    If 1.0 * unitsPerPx > 2 Then detailBoost = 1.0 * unitsPerPx - 2

    '' Per-pixel accumulators shared by the white and black version.
    Dim As Integer nPix = size * size
    Dim As Single Ptr accOut = CAllocate(nPix * SizeOf(Single))
    Dim As Single Ptr accFill = CAllocate(nPix * SizeOf(Single))
    Dim As Single Ptr accShade = CAllocate(nPix * SizeOf(Single))
    Dim As Single Ptr accDetail = CAllocate(nPix * SizeOf(Single))

    Dim As Integer pt
    For pt = PT_PAWN To PT_KING
        Dim As PieceShape Ptr shp = @Shapes(pt)
        Dim As Integer px, py, sx, sy, k
        For k = 0 To nPix - 1
            accOut[k] = 0 : accFill[k] = 0 : accShade[k] = 0 : accDetail[k] = 0
        Next
        For py = 0 To size - 1
            For px = 0 To size - 1
                Dim As Integer idx = py * size + px
                For sy = 0 To SS - 1
                    Dim As Single v = (py + (sy + 0.5) / SS) * unitsPerPx
                    For sx = 0 To SS - 1
                        Dim As Single u = (px + (sx + 0.5) / SS) * unitsPerPx
                        Dim As Integer sampleClass = 0          '' 0 none, 1 outline, 2 fill, 3 detail
                        '' Topmost filled shape containing the sample decides.
                        For k = shp->count - 1 To 0 Step -1
                            Dim As PiecePrim Ptr pr = @shp->prims(k)
                            If pr->kind <> PK_POLY AndAlso pr->kind <> PK_ELLIPSE Then Continue For
                            If u < pr->minX OrElse u > pr->maxX OrElse v < pr->minY OrElse v > pr->maxY Then Continue For
                            Dim As Single depth
                            If pr->kind = PK_ELLIPSE Then
                                depth = EllipseDepth(*pr, u, v)
                                If depth < 0 Then Continue For
                            Else
                                If Not PolyInside(*pr, u, v) Then Continue For
                                depth = PolyEdgeDist(*pr, u, v, True)
                            End If
                            sampleClass = IIf(depth < strokeW, 1, 2)
                            Exit For
                        Next
                        If sampleClass <> 0 Then
                            For k = 0 To shp->count - 1
                                Dim As PiecePrim Ptr pr = @shp->prims(k)
                                If pr->kind = PK_LINE Then
                                    If u >= pr->minX AndAlso u <= pr->maxX AndAlso v >= pr->minY AndAlso v <= pr->maxY Then
                                        If PolyEdgeDist(*pr, u, v, False) < (pr->w + detailBoost) / 2 Then sampleClass = 3
                                    End If
                                ElseIf pr->kind = PK_DOT Then
                                    Dim As Single ddx = u - pr->cx, ddy = v - pr->cy
                                    If Sqr(ddx * ddx + ddy * ddy) < pr->rx + detailBoost / 2 Then sampleClass = 3
                                End If
                            Next
                        End If
                        Select Case sampleClass
                        Case 1 : accOut[idx] += 1
                        Case 2
                            accFill[idx] += 1
                            '' Light from the upper left: -1 (shadow) .. +1 (highlight)
                            Dim As Single sh = (50 - u) / 50 * 0.7 + (45 - v) / 45 * 0.3
                            accShade[idx] += sh
                        Case 3 : accDetail[idx] += 1
                        End Select
                    Next
                Next
            Next
        Next

        '' Colourise for both sides.
        Dim As Integer side
        For side = SIDE_WHITE To SIDE_BLACK
            Dim As Any Ptr img = ImageCreate(size, size, RGBA(0, 0, 0, 0), 32)
            Dim As Any Ptr pixAny
            Dim As Long pitch
            ImageInfo img, , , , pitch, pixAny
            Dim As Single fillR, fillG, fillB, amp, outR, outG, outB, detR, detG, detB
            If side = SIDE_WHITE Then
                fillR = 242 : fillG = 236 : fillB = 222 : amp = 22
                outR = 35 : outG = 32 : outB = 30
                detR = 35 : detG = 32 : detB = 30
                If style = PIECESET_BOLD Then
                    fillR = 255 : fillG = 253 : fillB = 246 : amp = 8
                    outR = 0 : outG = 0 : outB = 0
                    detR = 0 : detG = 0 : detB = 0
                End If
            Else
                fillR = 62 : fillG = 62 : fillB = 70 : amp = 30
                outR = 12 : outG = 12 : outB = 14
                detR = 205 : detG = 200 : detB = 190
                If style = PIECESET_BOLD Then
                    fillR = 30 : fillG = 30 : fillB = 36 : amp = 14
                    outR = 0 : outG = 0 : outB = 0
                    detR = 255 : detG = 255 : detB = 255
                End If
            End If
            Const NS = SS * SS
            For py = 0 To size - 1
                Dim As ULong Ptr rowPtr = Cast(ULong Ptr, Cast(UByte Ptr, pixAny) + py * pitch)
                For px = 0 To size - 1
                    Dim As Integer idx = py * size + px
                    Dim As Single tot = accOut[idx] + accFill[idx] + accDetail[idx]
                    If tot <= 0 Then Continue For
                    Dim As Single r = outR * accOut[idx] + fillR * accFill[idx] + amp * accShade[idx] + detR * accDetail[idx]
                    Dim As Single g = outG * accOut[idx] + fillG * accFill[idx] + amp * accShade[idx] + detG * accDetail[idx]
                    Dim As Single b = outB * accOut[idx] + fillB * accFill[idx] + amp * accShade[idx] + detB * accDetail[idx]
                    r /= tot : g /= tot : b /= tot
                    If r < 0 Then r = 0
                    If g < 0 Then g = 0
                    If b < 0 Then b = 0
                    If r > 255 Then r = 255
                    If g > 255 Then g = 255
                    If b > 255 Then b = 255
                    rowPtr[px] = RGBA(CInt(r), CInt(g), CInt(b), CInt(255 * tot / NS))
                Next
            Next
            set.img(MAKE_PIECE(side, pt)) = img
        Next
    Next

    Deallocate accOut
    Deallocate accFill
    Deallocate accShade
    Deallocate accDetail
End Sub

Sub Pieces_Draw(ByRef set As PieceImages, ByVal pc As Integer, ByVal x As Integer, ByVal y As Integer)
    If pc < 0 OrElse pc > 15 Then Exit Sub
    If set.img(pc) = 0 Then Exit Sub
    Put (x, y), set.img(pc), Alpha
End Sub
