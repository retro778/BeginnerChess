'' =====================================================================
'' BeginnerChess - tests/test_gfx.bas
'' Colour arithmetic and drawing into the (headless) screen. These checks
'' matter most on 32-bit Windows, where unsigned colour values once made
'' gradients come out as coloured stripes.
'' =====================================================================
#include once "../modules/gfx.bi"

Dim Shared TestsPassed As Integer = 0
Dim Shared TestsFailed As Integer = 0
Dim Shared InGraphics As Boolean = False     '' Print would draw into the screen
Dim Shared Deferred As String

Sub Check(ByVal ok As Boolean, ByRef testName As Const String, ByRef detail As Const String = "")
    If ok Then
        TestsPassed += 1
    Else
        TestsFailed += 1
        Dim As String msg = "  FAIL: " & testName & IIf(detail <> "", "  (" & detail & ")", "")
        If InGraphics Then Deferred &= msg & Chr(10) Else Print msg
    End If
End Sub

Function Hex6(ByVal c As ULong) As String
    Return Hex(c And &hFFFFFF, 6)
End Function

Function IsClose(ByVal a As Integer, ByVal b As Integer) As Boolean
    Return Abs(a - b) <= 2
End Function

Sub TestColourMath()
    Print "Colour arithmetic..."
    '' Darker to lighter and lighter to darker: both must stay in range.
    Dim As ULong light = RGB(200, 150, 100), dark = RGB(20, 30, 40)
    Dim As ULong m = Color_Mix(light, dark, 0.5)
    Check IsClose(ARGB_R(m), 110) AndAlso IsClose(ARGB_G(m), 90) AndAlso IsClose(ARGB_B(m), 70) _
          AndAlso ARGB_A(m) = 255, "mix towards a darker colour", Hex6(m) & " a=" & ARGB_A(m)
    m = Color_Mix(dark, light, 0.25)
    Check IsClose(ARGB_R(m), 65) AndAlso IsClose(ARGB_G(m), 60) AndAlso IsClose(ARGB_B(m), 55), _
          "mix towards a lighter colour", Hex6(m)
    Check ARGB_R(dark) - ARGB_R(light) = -180, "channel differences are signed", Str(ARGB_R(dark) - ARGB_R(light))
    m = Color_Mix(RGBA(10, 10, 10, 255), RGBA(10, 10, 10, 0), 0.5)
    Check IsClose(ARGB_A(m), 128), "alpha mixes too", Str(ARGB_A(m))
    m = Color_Shade(RGB(100, 200, 50), 0.5)
    Check IsClose(ARGB_R(m), 50) AndAlso IsClose(ARGB_G(m), 100) AndAlso IsClose(ARGB_B(m), 25), "shade darker", Hex6(m)
    m = Color_Shade(RGB(200, 200, 200), 2)
    Check ARGB_R(m) = 255 AndAlso ARGB_G(m) = 255, "shade lighter is clamped", Hex6(m)
    m = Color_WithAlpha(RGB(1, 2, 3), 77)
    Check ARGB_A(m) = 77 AndAlso ARGB_B(m) = 3, "set alpha", Hex(m)
End Sub

Sub TestDrawing()
    Print "Drawing..."
    InGraphics = True
    Check Gfx_Open(64, 64, False, True, "test"), "headless screen opens"
    '' The menu background: lighter at the top, darker at the bottom.
    Dim As ULong cTop = RGB(44, 72, 108), cBottom = RGB(22, 34, 54)
    Gfx_GradientRect(0, 0, 64, 64, cTop, cBottom)
    Dim As ULong p0 = Point(10, 0), pMid = Point(10, 32), pEnd = Point(10, 63)
    Check (p0 And &hFFFFFF) = (cTop And &hFFFFFF), "gradient starts with the top colour", Hex6(p0)
    Check (pEnd And &hFFFFFF) = (cBottom And &hFFFFFF), "gradient ends with the bottom colour", Hex6(pEnd)
    Check IsClose(ARGB_R(pMid), 33) AndAlso IsClose(ARGB_G(pMid), 53) AndAlso IsClose(ARGB_B(pMid), 81), _
          "gradient middle is in between (no stripes)", Hex6(pMid)
    Dim As Integer y, bad = 0
    For y = 1 To 63
        If ARGB_R(Point(5, y)) > ARGB_R(Point(5, y - 1)) Then bad += 1
    Next
    Check bad = 0, "gradient gets darker row by row", bad & " rows brighter than the row above"
    '' Translucent drawing blends with what is below.
    Gfx_FillRect(0, 0, 64, 64, RGB(0, 0, 200))
    Gfx_FillRect(0, 0, 64, 64, RGBA(200, 0, 0, 128))
    Dim As ULong b = Point(30, 30)
    Check IsClose(ARGB_R(b), 100) AndAlso IsClose(ARGB_B(b), 100), "translucent fill blends", Hex6(b)
    Screen 0
    InGraphics = False
    If Deferred <> "" Then Print Deferred;
End Sub

Print "BeginnerChess graphics tests"
TestColourMath()
TestDrawing()
Print
Print "Passed: " & TestsPassed & "   Failed: " & TestsFailed
If TestsFailed > 0 Then End 1
End 0
