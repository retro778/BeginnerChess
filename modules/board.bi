'' =====================================================================
'' BeginnerChess - board.bi
'' Drawing the chess board: themes, square highlights, coordinates,
'' pieces, and converting between screen pixels and squares.
'' This module only DISPLAYS a position; it never decides legality.
'' =====================================================================
#pragma once
#include once "chessdefs.bi"
#include once "pieces.bi"

Enum BoardThemeId
    THEME_CLASSIC = 0
    THEME_WOOD
    THEME_MARBLE
    THEME_SIMPLE
    THEME_CONTRAST
    THEME_COUNT
End Enum

Type BoardView
    x           As Integer      '' top-left of square a8 (or h1 when flipped)
    y           As Integer
    sqSize      As Integer
    margin      As Integer      '' frame width around the squares
    flipped     As Boolean      '' True = Black at the bottom
    theme       As Integer
    pieceSet    As Integer      '' PieceSetId
    showCoords  As Boolean
    pieces      As PieceImages
    boardImg    As Any Ptr      '' pre-rendered squares + frame
    builtSize   As Integer
    builtTheme  As Integer
    builtCoords As Boolean
    builtFlip   As Boolean
End Type

'' What to highlight in this frame (filled in by the game screen).
Type BoardMarks
    selectedSq  As Integer      '' NO_SQUARE if none
    lastFrom    As Integer
    lastTo      As Integer
    checkSq     As Integer      '' king in check
    hoverSq     As Integer      '' square under the mouse that is a legal target
    errorSq     As Integer      '' red flash for an illegal attempt
    errorAlpha  As Integer      '' 0..255 strength of the flash
    hintFrom    As Integer      '' suggested move (used by later phases)
    hintTo      As Integer
    hideSq      As Integer      '' piece not drawn here (dragged/animated)
    hideSq2     As Integer
    targets(0 To 127) As UByte  '' 1 = legal quiet move, 2 = legal capture
    highlight(0 To 127) As UByte '' teaching marks: 1 green, 2 red, 3 blue, 4 yellow
    arrowCount  As Integer
    arrowFrom(0 To 15) As Integer
    arrowTo(0 To 15) As Integer
    arrowColor(0 To 15) As Integer  '' 1 green, 2 red, 3 blue, 4 yellow
End Type

Const MARK_GREEN = 1
Const MARK_RED = 2
Const MARK_BLUE = 3
Const MARK_YELLOW = 4

Declare Sub Board_ClearMarks(ByRef mk As BoardMarks)
Declare Sub Board_AddArrow(ByRef mk As BoardMarks, ByVal fromSq As Integer, ByVal toSq As Integer, ByVal colorId As Integer)
'' Positions the board; (x, y) = top-left of the whole frame.
Declare Sub Board_Layout(ByRef bv As BoardView, ByVal x As Integer, ByVal y As Integer, ByVal sqSize As Integer)
Declare Function Board_OuterSize(ByRef bv As BoardView) As Integer
Declare Sub Board_Draw(ByRef bv As BoardView, ByRef p As Position, ByRef mk As BoardMarks)
Declare Function Board_SquareAt(ByRef bv As BoardView, ByVal mx As Integer, ByVal my As Integer) As Integer
Declare Sub Board_SquareXY(ByRef bv As BoardView, ByVal sq As Integer, ByRef px As Integer, ByRef py As Integer)
Declare Sub Board_DrawPiece(ByRef bv As BoardView, ByVal pc As Integer, ByVal px As Integer, ByVal py As Integer)
Declare Function Board_ThemeName(ByVal theme As Integer) As String
Declare Sub Board_Free(ByRef bv As BoardView)
