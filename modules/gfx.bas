'' =====================================================================
'' BeginnerChess - gfx.bas
'' Drawing helpers and the smooth text renderer. See gfx.bi.
'' =====================================================================
#include once "gfx.bi"

Dim Shared ScreenW As Integer = 0
Dim Shared ScreenH As Integer = 0
Dim Shared DesktopW As Integer = 0
Dim Shared DesktopH As Integer = 0

Sub Gfx_DesktopSize(ByRef w As Integer, ByRef h As Integer)
    If DesktopW = 0 Then
        '' Before ScreenRes, ScreenInfo reports the desktop mode.
        Dim As Long dw, dh
        ScreenInfo dw, dh
        DesktopW = dw : DesktopH = dh
        If DesktopW <= 0 OrElse DesktopH <= 0 Then DesktopW = 1024 : DesktopH = 768
    End If
    w = DesktopW
    h = DesktopH
End Sub

'' ---------------------------------------------------------------------
'' Colours
'' ---------------------------------------------------------------------
Function Color_Mix(ByVal a As ULong, ByVal b As ULong, ByVal t As Single) As ULong
    If t <= 0 Then Return a
    If t >= 1 Then Return b
    Dim As Integer ca = ARGB_A(a) + (ARGB_A(b) - ARGB_A(a)) * t
    Dim As Integer cr = ARGB_R(a) + (ARGB_R(b) - ARGB_R(a)) * t
    Dim As Integer cg = ARGB_G(a) + (ARGB_G(b) - ARGB_G(a)) * t
    Dim As Integer cb = ARGB_B(a) + (ARGB_B(b) - ARGB_B(a)) * t
    Return RGBA(cr, cg, cb, ca)
End Function

Function Color_WithAlpha(ByVal c As ULong, ByVal alpha As Integer) As ULong
    If alpha < 0 Then alpha = 0
    If alpha > 255 Then alpha = 255
    Return (c And &h00FFFFFF) Or (CULng(alpha) Shl 24)
End Function

Function Color_Shade(ByVal c As ULong, ByVal factor As Single) As ULong
    Dim As Integer r = ARGB_R(c) * factor, g = ARGB_G(c) * factor, b = ARGB_B(c) * factor
    If r > 255 Then r = 255
    If g > 255 Then g = 255
    If b > 255 Then b = 255
    Return RGBA(r, g, b, ARGB_A(c))
End Function

'' ---------------------------------------------------------------------
'' Window
'' ---------------------------------------------------------------------
Function Gfx_Open(ByVal w As Integer, ByVal h As Integer, ByVal fullscreen As Boolean, _
                  ByVal headless As Boolean, ByRef title As Const String) As Boolean
    Dim As Integer dw, dh
    If ScreenW = 0 Then Gfx_DesktopSize(dw, dh)        '' remember the desktop size first
    Dim As Integer flags = 0
    If headless Then
        flags Or= FB.GFX_NULL
    ElseIf fullscreen Then
        flags Or= FB.GFX_FULLSCREEN
    Else
        flags Or= FB.GFX_WINDOWED
    End If
    If ScreenRes(w, h, 32, 2, flags) <> 0 Then
        '' Fullscreen may be refused by the system: fall back to a window.
        If fullscreen AndAlso Not headless Then
            If ScreenRes(w, h, 32, 2, FB.GFX_WINDOWED) <> 0 Then Return False
        Else
            Return False
        End If
    End If
    ScreenW = w
    ScreenH = h
    WindowTitle title
    Width w \ 8, h \ 16        '' selects the 8x16 built-in font
    ScreenSet 1, 0             '' draw on page 1, show page 0
    Text_Init()
    Return True
End Function

Sub Gfx_Present()
    ScreenCopy 1, 0
End Sub

Function Gfx_Width() As Integer
    Return ScreenW
End Function

Function Gfx_Height() As Integer
    Return ScreenH
End Function

Function Gfx_SaveScreenshot(ByRef fileName As Const String) As Boolean
    Return BSave(fileName, 0) = 0
End Function

'' ---------------------------------------------------------------------
'' Pixel blending
'' fbgfx's GFX_ALPHA_PRIMITIVES flag is not honoured by every driver
'' (e.g. the headless driver), so translucent drawing is done here by
'' writing to the frame buffer directly. Works on the screen work page
'' (target = 0) or on an fbgfx image buffer.
'' ---------------------------------------------------------------------
Private Function GetBuffer(ByVal target As Any Ptr, ByRef w As Integer, ByRef h As Integer, _
                           ByRef pitch As Integer, ByRef isImage As Boolean) As UByte Ptr
    If target = 0 Then
        Dim As Long sw, sh, sp
        ScreenInfo sw, sh, , , sp
        w = sw : h = sh : pitch = sp
        isImage = False
        Return ScreenPtr()
    End If
    Dim As Long iw, ih, ip
    Dim As Any Ptr pix
    ImageInfo target, iw, ih, , ip, pix
    w = iw : h = ih : pitch = ip
    isImage = True
    Return pix
End Function

'' Blends colour c (with its alpha) over pixels x0..x1 of row y.
Private Sub BlendSpan(ByVal target As Any Ptr, ByVal x0 As Integer, ByVal x1 As Integer, _
                      ByVal y As Integer, ByVal c As ULong)
    Dim As Integer w, h, pitch
    Dim As Boolean isImage
    Dim As UByte Ptr buf = GetBuffer(target, w, h, pitch, isImage)
    If buf = 0 OrElse y < 0 OrElse y >= h Then Exit Sub
    If x0 < 0 Then x0 = 0
    If x1 >= w Then x1 = w - 1
    If x1 < x0 Then Exit Sub
    Dim As ULong Ptr row = Cast(ULong Ptr, buf + y * pitch)
    Dim As Integer a = ARGB_A(c)
    If a <= 0 Then Exit Sub
    Dim As Integer x
    If a >= 255 Then
        For x = x0 To x1 : row[x] = c : Next
        Exit Sub
    End If
    Dim As Integer sr = ARGB_R(c), sg = ARGB_G(c), sb = ARGB_B(c), ia = 255 - a
    For x = x0 To x1
        Dim As ULong d = row[x]
        Dim As Integer dr = ARGB_R(d), dg = ARGB_G(d), db = ARGB_B(d), da = ARGB_A(d)
        Dim As Integer outA = 255
        If isImage Then
            '' Porter-Duff "over" so translucent images stay translucent.
            outA = a + (da * ia) \ 255
            If outA <= 0 Then
                row[x] = 0
                Continue For
            End If
            dr = (sr * a + (dr * da * ia) \ 255) \ outA
            dg = (sg * a + (dg * da * ia) \ 255) \ outA
            db = (sb * a + (db * da * ia) \ 255) \ outA
        Else
            dr = (sr * a + dr * ia) \ 255
            dg = (sg * a + dg * ia) \ 255
            db = (sb * a + db * ia) \ 255
        End If
        row[x] = RGBA(dr, dg, db, outA)
    Next
End Sub

'' ---------------------------------------------------------------------
'' Shapes
'' ---------------------------------------------------------------------
Sub Gfx_FillRect(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, ByVal c As ULong)
    If w <= 0 OrElse h <= 0 Then Exit Sub
    Dim As Integer i
    For i = y To y + h - 1
        BlendSpan(0, x, x + w - 1, i, c)
    Next
End Sub

Sub Gfx_GradientRect(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, _
                     ByVal cTop As ULong, ByVal cBottom As ULong)
    Dim As Integer i
    For i = 0 To h - 1
        BlendSpan(0, x, x + w - 1, y + i, Color_Mix(cTop, cBottom, i / IIf(h > 1, h - 1, 1)))
    Next
End Sub

'' Draws one pixel row of coverage values as runs (full) and blended pixels (partial).
Private Sub EmitCoverageRow(ByVal x0 As Integer, ByVal y As Integer, cov() As Single, ByVal n As Integer, _
                            ByVal c As ULong, ByVal target As Any Ptr)
    Dim As Integer baseA = ARGB_A(c), i = 0
    Do While i < n
        If cov(i) >= 0.999 Then
            Dim As Integer j = i
            Do While j + 1 < n AndAlso cov(j + 1) >= 0.999
                j += 1
            Loop
            BlendSpan(target, x0 + i, x0 + j, y, c)
            i = j + 1
        Else
            If cov(i) > 0.004 Then
                BlendSpan(target, x0 + i, x0 + i, y, Color_WithAlpha(c, CInt(baseA * cov(i))))
            End If
            i += 1
        End If
    Loop
End Sub

Sub Gfx_RoundRect(ByVal x As Single, ByVal y As Single, ByVal w As Single, ByVal h As Single, _
                  ByVal r As Single, ByVal c As ULong, ByVal target As Any Ptr = 0)
    If w <= 0 OrElse h <= 0 Then Exit Sub
    If r > w / 2 Then r = w / 2
    If r > h / 2 Then r = h / 2
    If r < 0 Then r = 0
    Const SUBROWS = 4
    Dim As Integer px0 = Int(x), px1 = Int(x + w + 0.999)
    Dim As Integer n = px1 - px0 + 1
    Dim As Single cov(0 To n)
    Dim As Single xl(0 To SUBROWS - 1), xr(0 To SUBROWS - 1)
    Dim As Integer row, s, i
    For row = Int(y) To Int(y + h + 0.999) - 1
        '' Span of every sub-row (rounded corners make it narrower).
        Dim As Single xlMin = 1e9, xlMax = -1e9, xrMin = 1e9, xrMax = -1e9
        Dim As Integer used = 0
        For s = 0 To SUBROWS - 1
            Dim As Single sy = row + (s + 0.5) / SUBROWS
            If sy < y OrElse sy > y + h Then
                xl(s) = 1 : xr(s) = 0                      '' empty sub-row
                xlMax = 1e9 : xrMin = -1e9                 '' no fully covered pixel
                Continue For
            End If
            Dim As Single dy = 0, inset = 0
            If sy < y + r Then dy = (y + r) - sy
            If sy > y + h - r Then dy = sy - (y + h - r)
            If dy > 0 Then inset = r - Sqr(Abs(r * r - dy * dy))
            xl(s) = x + inset : xr(s) = x + w - inset
            If xl(s) < xlMin Then xlMin = xl(s)
            If xl(s) > xlMax Then xlMax = xl(s)
            If xr(s) < xrMin Then xrMin = xr(s)
            If xr(s) > xrMax Then xrMax = xr(s)
            used += 1
        Next
        If used = 0 Then Continue For
        '' Pixels between the innermost edges are fully covered: one span.
        Dim As Integer fullL = Int(xlMax + 0.999), fullR = Int(xrMin) - 1
        If fullR >= fullL Then BlendSpan(target, fullL, fullR, row, c)
        '' Edge pixels get anti-aliased coverage.
        Dim As Integer e0, e1, pass
        For pass = 0 To 1
            If pass = 0 Then
                e0 = Int(xlMin) : e1 = IIf(fullR >= fullL, fullL - 1, Int(xrMax))
            Else
                If fullR < fullL Then Exit For
                e0 = fullR + 1 : e1 = Int(xrMax)
            End If
            For i = e0 To e1
                Dim As Single total = 0
                For s = 0 To SUBROWS - 1
                    Dim As Single a = i, b = i + 1
                    If a < xl(s) Then a = xl(s)
                    If b > xr(s) Then b = xr(s)
                    If b > a Then total += (b - a) / SUBROWS
                Next
                If total > 0.004 Then BlendSpan(target, i, i, row, Color_WithAlpha(c, CInt(ARGB_A(c) * IIf(total > 1, 1, total))))
            Next
        Next
    Next
End Sub

Sub Gfx_Panel(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, _
              ByVal r As Integer, ByVal fill As ULong, ByVal border As ULong, _
              ByVal shadow As Boolean = True)
    If shadow Then
        Gfx_RoundRect(x - 1, y + 3, w + 2, h + 4, r + 2, RGBA(0, 0, 0, 28))
        Gfx_RoundRect(x, y + 2, w, h + 2, r + 1, RGBA(0, 0, 0, 40))
    End If
    Gfx_RoundRect(x, y, w, h, r, border)
    Gfx_RoundRect(x + 2, y + 2, w - 4, h - 4, IIf(r > 2, r - 2, 0), fill)
End Sub

Sub Gfx_FillCircle(ByVal cx As Single, ByVal cy As Single, ByVal r As Single, ByVal c As ULong, _
                   ByVal target As Any Ptr = 0)
    Dim As Integer x0 = Int(cx - r - 1), x1 = Int(cx + r + 1)
    Dim As Integer y0 = Int(cy - r - 1), y1 = Int(cy + r + 1)
    Dim As Integer n = x1 - x0 + 1, px, py
    Dim As Single cov(0 To n)
    For py = y0 To y1
        Dim As Single dy = py + 0.5 - cy
        For px = x0 To x1
            Dim As Single dx = px + 0.5 - cx
            Dim As Single v = r - Sqr(dx * dx + dy * dy) + 0.5
            If v < 0 Then v = 0
            If v > 1 Then v = 1
            cov(px - x0) = v
        Next
        EmitCoverageRow(x0, py, cov(), n, c, target)
    Next
End Sub

Sub Gfx_Ring(ByVal cx As Single, ByVal cy As Single, ByVal r As Single, ByVal thickness As Single, _
             ByVal c As ULong)
    Dim As Single rIn = r - thickness
    Dim As Integer x0 = Int(cx - r - 1), x1 = Int(cx + r + 1)
    Dim As Integer y0 = Int(cy - r - 1), y1 = Int(cy + r + 1)
    Dim As Integer n = x1 - x0 + 1, px, py
    Dim As Single cov(0 To n)
    For py = y0 To y1
        Dim As Single dy = py + 0.5 - cy
        For px = x0 To x1
            Dim As Single dx = px + 0.5 - cx
            Dim As Single d = Sqr(dx * dx + dy * dy)
            Dim As Single vo = r - d + 0.5, vi = rIn - d + 0.5
            If vo < 0 Then vo = 0
            If vo > 1 Then vo = 1
            If vi < 0 Then vi = 0
            If vi > 1 Then vi = 1
            cov(px - x0) = vo - vi
        Next
        EmitCoverageRow(x0, py, cov(), n, c, 0)
    Next
End Sub

Sub Gfx_FillPolygon(xs() As Single, ys() As Single, ByVal n As Integer, ByVal c As ULong)
    If n < 3 Then Exit Sub
    Dim As Single minX = xs(0), maxX = xs(0), minY = ys(0), maxY = ys(0)
    Dim As Integer i, j
    For i = 1 To n - 1
        If xs(i) < minX Then minX = xs(i)
        If xs(i) > maxX Then maxX = xs(i)
        If ys(i) < minY Then minY = ys(i)
        If ys(i) > maxY Then maxY = ys(i)
    Next
    Const SUBROWS = 4
    Dim As Integer px0 = Int(minX), px1 = Int(maxX) + 1
    Dim As Integer cnt = px1 - px0 + 1
    Dim As Single cov(0 To cnt)
    Dim As Single xsect(0 To 63)
    Dim As Integer row, sr
    For row = Int(minY) To Int(maxY)
        For i = 0 To cnt : cov(i) = 0 : Next
        For sr = 0 To SUBROWS - 1
            Dim As Single sy = row + (sr + 0.5) / SUBROWS
            '' Edge crossings on this sub-row
            Dim As Integer nx = 0
            j = n - 1
            For i = 0 To n - 1
                If (ys(i) > sy) <> (ys(j) > sy) AndAlso nx < 64 Then
                    xsect(nx) = xs(i) + (sy - ys(i)) * (xs(j) - xs(i)) / (ys(j) - ys(i))
                    nx += 1
                End If
                j = i
            Next
            '' Sort crossings (few of them)
            Dim As Integer a, b
            For a = 0 To nx - 2
                For b = a + 1 To nx - 1
                    If xsect(b) < xsect(a) Then Swap xsect(a), xsect(b)
                Next
            Next
            '' Fill between pairs with fractional end coverage
            For a = 0 To nx - 2 Step 2
                Dim As Single xl = xsect(a), xr = xsect(a + 1)
                For i = Int(xl) - px0 To Int(xr) - px0
                    If i < 0 OrElse i > cnt Then Continue For
                    Dim As Single l = px0 + i, r = l + 1
                    If l < xl Then l = xl
                    If r > xr Then r = xr
                    If r > l Then cov(i) += (r - l) / SUBROWS
                Next
            Next
        Next
        EmitCoverageRow(px0, row, cov(), cnt, c, 0)
    Next
End Sub

Sub Gfx_Arrow(ByVal x1 As Single, ByVal y1 As Single, ByVal x2 As Single, ByVal y2 As Single, _
              ByVal thickness As Single, ByVal c As ULong)
    Dim As Single dx = x2 - x1, dy = y2 - y1
    Dim As Single L = Sqr(dx * dx + dy * dy)
    If L < 1 Then Exit Sub
    Dim As Single ux = dx / L, uy = dy / L          '' along the arrow
    Dim As Single nx = -uy, ny = ux                   '' across the arrow
    Dim As Single headLen = thickness * 2.6, headW = thickness * 1.6, hw = thickness / 2
    If headLen > L * 0.6 Then headLen = L * 0.6
    Dim As Single bx = x2 - ux * headLen, by = y2 - uy * headLen
    Dim As Single xs(0 To 6), ys(0 To 6)
    xs(0) = x1 + nx * hw : ys(0) = y1 + ny * hw
    xs(1) = bx + nx * hw : ys(1) = by + ny * hw
    xs(2) = bx + nx * headW : ys(2) = by + ny * headW
    xs(3) = x2 : ys(3) = y2
    xs(4) = bx - nx * headW : ys(4) = by - ny * headW
    xs(5) = bx - nx * hw : ys(5) = by - ny * hw
    xs(6) = x1 - nx * hw : ys(6) = y1 - ny * hw
    Gfx_FillPolygon(xs(), ys(), 7, c)
End Sub

Sub Gfx_DoneBadge(ByVal cx As Single, ByVal cy As Single, ByVal r As Single)
    Gfx_FillCircle(cx, cy, r, RGB(40, 150, 60))
    '' Tick: two thick strokes as one polygon
    Dim As Single xs(0 To 5), ys(0 To 5), t = r * 0.18
    xs(0) = cx - r * 0.5 : ys(0) = cy - r * 0.02
    xs(1) = cx - r * 0.12 : ys(1) = cy + r * 0.38
    xs(2) = cx + r * 0.55 : ys(2) = cy - r * 0.38
    xs(3) = cx + r * 0.55 - t : ys(3) = cy - r * 0.38 - t
    xs(4) = cx - r * 0.12 : ys(4) = cy + r * 0.38 - t * 1.6
    xs(5) = cx - r * 0.5 + t * 0.8 : ys(5) = cy - r * 0.02 - t
    Gfx_FillPolygon(xs(), ys(), 6, RGB(255, 255, 255))
End Sub

'' ---------------------------------------------------------------------
'' Text renderer
''
'' The 8x16 built-in font is captured once, enlarged 4x with the EPX
'' ("scale2x") algorithm twice, which rounds off diagonal stair-steps,
'' and then box-filtered down to the requested size. The result is an
'' anti-aliased fbgfx custom font (one per size/colour pair, cached).
'' ---------------------------------------------------------------------
Const FONT_FIRST = 32
Const FONT_LAST = 255
Const FONT_COUNT = FONT_LAST - FONT_FIRST + 1
Const MASTER_W = 32
Const MASTER_H = 64

Dim Shared FontMaster(0 To FONT_COUNT - 1, 0 To MASTER_H - 1, 0 To MASTER_W - 1) As UByte
Dim Shared FontReady As Boolean = False

Const FONT_CACHE_MAX = 48
Type FontCacheEntry
    size As Integer
    clr  As ULong
    img  As Any Ptr
End Type
Dim Shared FontCache(0 To FONT_CACHE_MAX - 1) As FontCacheEntry
Dim Shared FontCacheCount As Integer = 0

'' Coverage maps per size (independent of colour).
Const COV_CACHE_MAX = 16
Type CoverageEntry
    size As Integer
    gw   As Integer
    data As UByte Ptr      '' FONT_COUNT * size * gw bytes
End Type
Dim Shared CovCache(0 To COV_CACHE_MAX - 1) As CoverageEntry
Dim Shared CovCount As Integer = 0

'' One EPX 2x enlargement of a w*h bitmap.
Private Sub Epx2x(src() As UByte, ByVal w As Integer, ByVal h As Integer, dst() As UByte)
    Dim As Integer x, y
    For y = 0 To h - 1
        For x = 0 To w - 1
            Dim As UByte p = src(y, x)
            Dim As UByte a = IIf(y > 0, src(y - 1, x), 0)
            Dim As UByte b = IIf(x < w - 1, src(y, x + 1), 0)
            Dim As UByte c = IIf(x > 0, src(y, x - 1), 0)
            Dim As UByte d = IIf(y < h - 1, src(y + 1, x), 0)
            Dim As UByte p1 = p, p2 = p, p3 = p, p4 = p
            If c = a AndAlso c <> d AndAlso a <> b Then p1 = a
            If a = b AndAlso a <> c AndAlso b <> d Then p2 = b
            If d = c AndAlso d <> b AndAlso c <> a Then p3 = c
            If b = d AndAlso b <> a AndAlso d <> c Then p4 = d
            dst(y * 2, x * 2) = p1
            dst(y * 2, x * 2 + 1) = p2
            dst(y * 2 + 1, x * 2) = p3
            dst(y * 2 + 1, x * 2 + 1) = p4
        Next
    Next
End Sub

Sub Text_Init()
    If FontReady Then Exit Sub
    '' Render every character of the built-in font into a scratch image.
    Dim As Any Ptr scratch = ImageCreate(8, 16, RGB(0, 0, 0), 32)
    Dim As Integer ch, x, y
    Dim As UByte g16(0 To 15, 0 To 7), g32(0 To 31, 0 To 15), g64(0 To 63, 0 To 31)
    For ch = FONT_FIRST To FONT_LAST
        Line scratch, (0, 0)-(7, 15), RGB(0, 0, 0), BF
        Draw String scratch, (0, 0), Chr(ch), RGB(255, 255, 255)
        For y = 0 To 15
            For x = 0 To 7
                g16(y, x) = IIf((Point(x, y, scratch) And &hFFFFFF) <> 0, 1, 0)
            Next
        Next
        Epx2x(g16(), 8, 16, g32())
        Epx2x(g32(), 16, 32, g64())
        For y = 0 To MASTER_H - 1
            For x = 0 To MASTER_W - 1
                FontMaster(ch - FONT_FIRST, y, x) = g64(y, x)
            Next
        Next
    Next
    ImageDestroy scratch
    FontReady = True
End Sub

Private Function GetCoverage(ByVal size As Integer) As Integer
    Dim As Integer i
    For i = 0 To CovCount - 1
        If CovCache(i).size = size Then Return i
    Next
    If CovCount >= COV_CACHE_MAX Then
        '' Forget the oldest size.
        Deallocate CovCache(0).data
        For i = 1 To CovCount - 1
            CovCache(i - 1) = CovCache(i)
        Next
        CovCount -= 1
    End If
    Dim As Integer gw = size \ 2
    If gw < 3 Then gw = 3
    Dim As UByte Ptr dat = CAllocate(FONT_COUNT * size * gw)
    '' Box filter from the 32x64 master down to gw x size.
    Dim As Single sx = MASTER_W / gw, sy = MASTER_H / size
    Dim As Integer ch, x, y, mx, my
    For ch = 0 To FONT_COUNT - 1
        For y = 0 To size - 1
            Dim As Integer my0 = Int(y * sy), my1 = Int((y + 1) * sy + 0.999) - 1
            If my1 >= MASTER_H Then my1 = MASTER_H - 1
            If my1 < my0 Then my1 = my0
            For x = 0 To gw - 1
                Dim As Integer mx0 = Int(x * sx), mx1 = Int((x + 1) * sx + 0.999) - 1
                If mx1 >= MASTER_W Then mx1 = MASTER_W - 1
                If mx1 < mx0 Then mx1 = mx0
                Dim As Integer total = 0, hits = 0
                For my = my0 To my1
                    For mx = mx0 To mx1
                        total += 1
                        hits += FontMaster(ch, my, mx)
                    Next
                Next
                dat[(ch * size + y) * gw + x] = (hits * 255) \ total
            Next
        Next
    Next
    CovCache(CovCount).size = size
    CovCache(CovCount).gw = gw
    CovCache(CovCount).data = dat
    CovCount += 1
    Return CovCount - 1
End Function

Private Function GetFont(ByVal size As Integer, ByVal c As ULong) As Any Ptr
    Dim As Integer i
    For i = 0 To FontCacheCount - 1
        If FontCache(i).size = size AndAlso FontCache(i).clr = c Then Return FontCache(i).img
    Next
    If FontCacheCount >= FONT_CACHE_MAX Then
        ImageDestroy FontCache(0).img
        For i = 1 To FontCacheCount - 1
            FontCache(i - 1) = FontCache(i)
        Next
        FontCacheCount -= 1
    End If

    Dim As Integer ci = GetCoverage(size)
    Dim As Integer gw = CovCache(ci).gw
    Dim As UByte Ptr dat = CovCache(ci).data
    Dim As Any Ptr img = ImageCreate(FONT_COUNT * gw, size + 1, RGBA(0, 0, 0, 0), 32)

    Dim As Any Ptr pixAny
    Dim As Long pitch
    ImageInfo img, , , , pitch, pixAny
    Dim As UByte Ptr hdr = pixAny
    '' fbgfx custom font header in row 0: version, first char, last char, widths.
    hdr[0] = 0
    hdr[1] = FONT_FIRST
    hdr[2] = FONT_LAST
    For i = 0 To FONT_COUNT - 1
        hdr[3 + i] = gw
    Next

    Dim As Integer baseA = ARGB_A(c), ch, x, y
    Dim As ULong rgbPart = c And &h00FFFFFF
    For ch = 0 To FONT_COUNT - 1
        For y = 0 To size - 1
            Dim As ULong Ptr rowPtr = Cast(ULong Ptr, Cast(UByte Ptr, pixAny) + (y + 1) * pitch)
            For x = 0 To gw - 1
                Dim As Integer v = dat[(ch * size + y) * gw + x]
                rowPtr[ch * gw + x] = rgbPart Or (CULng((v * baseA) \ 255) Shl 24)
            Next
        Next
    Next

    FontCache(FontCacheCount).size = size
    FontCache(FontCacheCount).clr = c
    FontCache(FontCacheCount).img = img
    FontCacheCount += 1
    Return img
End Function

Sub Text_Draw(ByVal x As Integer, ByVal y As Integer, ByRef s As Const String, _
              ByVal size As Integer, ByVal c As ULong)
    If Len(s) = 0 OrElse size < 6 Then Exit Sub
    Draw String (x, y), s, , GetFont(size, c), Alpha
End Sub

Sub Text_DrawShadow(ByVal x As Integer, ByVal y As Integer, ByRef s As Const String, _
                    ByVal size As Integer, ByVal c As ULong, ByVal shadow As ULong)
    Dim As Integer off = 1 + size \ 24
    Text_Draw(x + off, y + off, s, size, shadow)
    Text_Draw(x, y, s, size, c)
End Sub

Function Text_Width(ByRef s As Const String, ByVal size As Integer) As Integer
    Dim As Integer gw = size \ 2
    If gw < 3 Then gw = 3
    Return Len(s) * gw
End Function

Sub Text_DrawCentered(ByVal cx As Integer, ByVal y As Integer, ByRef s As Const String, _
                      ByVal size As Integer, ByVal c As ULong)
    Text_Draw(cx - Text_Width(s, size) \ 2, y, s, size, c)
End Sub

Function Text_Wrap(ByRef s As Const String, ByVal size As Integer, ByVal maxWidth As Integer, _
                   lines() As String) As Integer
    Dim As Integer n = 0, i = 1, L = Len(s)
    Dim As String cur = "", word = ""
    Dim As Integer maxChars = maxWidth \ IIf(size \ 2 < 3, 3, size \ 2)
    If maxChars < 1 Then maxChars = 1

    #macro PUSH_LINE(txt)
        If n > UBound(lines) Then ReDim Preserve lines(0 To n + 15)
        lines(n) = txt
        n += 1
    #endmacro

    Do While i <= L + 1
        Dim As String c = IIf(i <= L, Mid(s, i, 1), " ")
        If c = " " OrElse c = "|" OrElse i > L Then
            '' Finish the current word.
            Do While Len(word) > maxChars          '' very long word: hard split
                If Len(cur) > 0 Then PUSH_LINE(cur) : cur = ""
                PUSH_LINE(Left(word, maxChars))
                word = Mid(word, maxChars + 1)
            Loop
            If Len(word) > 0 Then
                If Len(cur) = 0 Then
                    cur = word
                ElseIf Len(cur) + 1 + Len(word) <= maxChars Then
                    cur &= " " & word
                Else
                    PUSH_LINE(cur)
                    cur = word
                End If
            End If
            word = ""
            If c = "|" Then
                PUSH_LINE(cur)
                cur = ""
            End If
        Else
            word &= c
        End If
        i += 1
    Loop
    If Len(cur) > 0 Then PUSH_LINE(cur)
    Return n
End Function

Function Text_DrawWrapped(ByVal x As Integer, ByVal y As Integer, ByVal maxWidth As Integer, _
                          ByRef s As Const String, ByVal size As Integer, ByVal c As ULong, _
                          ByVal centered As Boolean = False) As Integer
    Dim As String lines()
    ReDim lines(0 To 15)
    Dim As Integer n = Text_Wrap(s, size, maxWidth, lines()), i
    Dim As Integer lineH = size + size \ 4
    For i = 0 To n - 1
        If centered Then
            Text_DrawCentered(x + maxWidth \ 2, y + i * lineH, lines(i), size, c)
        Else
            Text_Draw(x, y + i * lineH, lines(i), size, c)
        End If
    Next
    Return n * lineH
End Function

Function Text_FitSize(ByRef s As Const String, ByVal maxWidth As Integer, ByVal maxHeight As Integer, _
                      ByVal startSize As Integer, ByVal minSize As Integer) As Integer
    Dim As String lines()
    ReDim lines(0 To 15)
    Dim As Integer size = startSize
    Do While size > minSize
        Dim As Integer n = Text_Wrap(s, size, maxWidth, lines())
        If n * (size + size \ 4) <= maxHeight Then Exit Do
        size -= 1
    Loop
    Return size
End Function

Sub Text_Shutdown()
    Dim As Integer i
    For i = 0 To FontCacheCount - 1
        ImageDestroy FontCache(i).img
    Next
    FontCacheCount = 0
    For i = 0 To CovCount - 1
        Deallocate CovCache(i).data
    Next
    CovCount = 0
End Sub
