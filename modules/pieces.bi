'' =====================================================================
'' BeginnerChess - pieces.bi
'' Chess piece images. The default set ("Classic") is BeginnerChess's own
'' original vector artwork, drawn by the program itself at any size, so
'' no external image files are required. Graphics are not used by the
'' chess logic in any way.
'' =====================================================================
#pragma once
#include once "chessdefs.bi"
#include once "gfx.bi"

Enum PieceSetId
    PIECESET_CLASSIC = 0     '' traditional look, fine outlines
    PIECESET_BOLD            '' thick outlines and strong contrast (easier to see)
    PIECESET_COUNT
End Enum

'' A rendered set of 12 piece images at one pixel size.
Type PieceImages
    size As Integer
    style As Integer         '' PieceSetId
    img(0 To 15) As Any Ptr        '' indexed by piece code (PC_WP .. PC_BK)
End Type

'' Renders all pieces at the given size (pixels). Replaces previous images.
Declare Sub Pieces_Build(ByRef set As PieceImages, ByVal size As Integer, ByVal style As Integer = PIECESET_CLASSIC)
Declare Function Pieces_SetName(ByVal style As Integer) As String
Declare Sub Pieces_Free(ByRef set As PieceImages)
'' Draws a piece with its top-left corner at (x, y).
Declare Sub Pieces_Draw(ByRef set As PieceImages, ByVal pc As Integer, ByVal x As Integer, ByVal y As Integer)
