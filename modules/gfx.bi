'' =====================================================================
'' BeginnerChess - gfx.bi
'' Low-level drawing helpers on top of FreeBASIC's fbgfx library:
'' window setup, colours, anti-aliased shapes, and a smooth scalable
'' text renderer (built at run time from the built-in 8x16 font, so no
'' font files are needed).
'' =====================================================================
#pragma once
#include once "fbgfx.bi"

'' ---- Colours --------------------------------------------------------
'' Colour channels as *signed* integers. Without CInt the result stays an
'' unsigned ULong on 32-bit FreeBASIC, and differences such as
'' ARGB_R(b) - ARGB_R(a) wrap around instead of becoming negative.
#define ARGB_A(c) CInt(((c) Shr 24) And 255)
#define ARGB_R(c) CInt(((c) Shr 16) And 255)
#define ARGB_G(c) CInt(((c) Shr 8) And 255)
#define ARGB_B(c) CInt((c) And 255)

Declare Function Color_Mix(ByVal a As ULong, ByVal b As ULong, ByVal t As Single) As ULong
Declare Function Color_WithAlpha(ByVal c As ULong, ByVal alpha As Integer) As ULong
Declare Function Color_Shade(ByVal c As ULong, ByVal factor As Single) As ULong

'' ---- Window ---------------------------------------------------------
'' Opens the graphics window (double buffered). headless = render to
'' memory only (used for automated screenshots). Returns False on failure.
Declare Function Gfx_Open(ByVal w As Integer, ByVal h As Integer, ByVal fullscreen As Boolean, _
                          ByVal headless As Boolean, ByRef title As Const String) As Boolean
Declare Sub Gfx_Present()          '' shows the finished frame
'' Size of the desktop (measured before the first window is opened).
Declare Sub Gfx_DesktopSize(ByRef w As Integer, ByRef h As Integer)
Declare Function Gfx_Width() As Integer
Declare Function Gfx_Height() As Integer
Declare Function Gfx_SaveScreenshot(ByRef fileName As Const String) As Boolean

'' ---- Shapes (all accept alpha in the colour) ------------------------
Declare Sub Gfx_FillRect(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, ByVal c As ULong)
Declare Sub Gfx_GradientRect(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, _
                             ByVal cTop As ULong, ByVal cBottom As ULong)
Declare Sub Gfx_RoundRect(ByVal x As Single, ByVal y As Single, ByVal w As Single, ByVal h As Single, _
                          ByVal r As Single, ByVal c As ULong, ByVal target As Any Ptr = 0)
'' Rounded panel with a border and a soft drop shadow.
Declare Sub Gfx_Panel(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, _
                      ByVal r As Integer, ByVal fill As ULong, ByVal border As ULong, _
                      ByVal shadow As Boolean = True)
Declare Sub Gfx_FillCircle(ByVal cx As Single, ByVal cy As Single, ByVal r As Single, ByVal c As ULong, _
                           ByVal target As Any Ptr = 0)
Declare Sub Gfx_Ring(ByVal cx As Single, ByVal cy As Single, ByVal r As Single, ByVal thickness As Single, _
                     ByVal c As ULong)

'' Anti-aliased filled polygon (even-odd rule).
Declare Sub Gfx_FillPolygon(xs() As Single, ys() As Single, ByVal n As Integer, ByVal c As ULong)
'' Thick arrow from (x1,y1) to (x2,y2) with a triangular head.
Declare Sub Gfx_Arrow(ByVal x1 As Single, ByVal y1 As Single, ByVal x2 As Single, ByVal y2 As Single, _
                      ByVal thickness As Single, ByVal c As ULong)

'' A white tick mark on a green disc (for "done").
Declare Sub Gfx_DoneBadge(ByVal cx As Single, ByVal cy As Single, ByVal r As Single)

'' ---- Text -----------------------------------------------------------
'' size = text height in pixels (character width is size / 2).
Declare Sub Text_Init()
Declare Sub Text_Draw(ByVal x As Integer, ByVal y As Integer, ByRef s As Const String, _
                      ByVal size As Integer, ByVal c As ULong)
Declare Sub Text_DrawShadow(ByVal x As Integer, ByVal y As Integer, ByRef s As Const String, _
                            ByVal size As Integer, ByVal c As ULong, ByVal shadow As ULong)
Declare Sub Text_DrawCentered(ByVal cx As Integer, ByVal y As Integer, ByRef s As Const String, _
                              ByVal size As Integer, ByVal c As ULong)
Declare Function Text_Width(ByRef s As Const String, ByVal size As Integer) As Integer
'' Word-wraps text into lines that fit maxWidth. Returns the line count.
'' A "|" character forces a line break.
Declare Function Text_Wrap(ByRef s As Const String, ByVal size As Integer, ByVal maxWidth As Integer, _
                           lines() As String) As Integer
'' Draws wrapped text; returns the height used.
Declare Function Text_DrawWrapped(ByVal x As Integer, ByVal y As Integer, ByVal maxWidth As Integer, _
                                  ByRef s As Const String, ByVal size As Integer, ByVal c As ULong, _
                                  ByVal centered As Boolean = False) As Integer
'' Largest size (from startSize down to minSize) at which the wrapped text
'' fits into maxWidth x maxHeight.
Declare Function Text_FitSize(ByRef s As Const String, ByVal maxWidth As Integer, ByVal maxHeight As Integer, _
                              ByVal startSize As Integer, ByVal minSize As Integer) As Integer
Declare Sub Text_Shutdown()
