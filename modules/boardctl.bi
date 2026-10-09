'' =====================================================================
'' BeginnerChess - boardctl.bi
'' A reusable interactive board for lessons, puzzles and other screens:
'' selection with legal-move markers, click-click and drag-and-drop,
'' promotion chooser, move animation with sound, and a red flash plus a
'' friendly explanation for illegal attempts. Legality always comes from
'' rules.bas.
'' =====================================================================
#pragma once
#include once "board.bi"
#include once "gui.bi"
#include once "explain.bi"
#include once "audio.bi"
#include once "settings.bi"

Type BoardControl
    selected     As Integer
    dragArmed    As Boolean
    dragging     As Boolean
    deselectOnUp As Boolean
    dragSq       As Integer
    pressX       As Integer
    pressY       As Integer
    promoActive  As Boolean
    promoFrom    As Integer
    promoTo      As Integer
    errorSq      As Integer
    errorTime    As Double
    animActive   As Boolean
    animStart    As Double
    animDur      As Double
    animFrom     As Integer
    animTo       As Integer
    animPc       As Integer
    anim2From    As Integer
    anim2To      As Integer
    anim2Pc      As Integer
    pendingSound As Integer
    legal        As MoveList
    legalKey     As ULongInt
    legalPly     As Integer
    lastFrom     As Integer       '' last move shown on the board
    lastTo       As Integer
End Type

Declare Sub BC_Reset(ByRef bc As BoardControl)
'' Draws the board and handles the mouse. Returns True when the player
'' completed a legal move (outMove). On an illegal attempt illegalText
'' gets an explanation. allowInput = False shows the board only.
Declare Function BC_Frame(ByRef bc As BoardControl, ByRef bv As BoardView, ByRef p As Position, _
                          ByVal allowInput As Boolean, ByRef extra As BoardMarks, _
                          ByRef outMove As ChessMove, ByRef illegalText As String) As Boolean
'' Starts the slide animation for move m (p = position AFTER the move)
'' and plays the matching sound when the piece lands.
Declare Sub BC_AnimateMove(ByRef bc As BoardControl, ByRef p As Position, ByRef m As ChessMove)
Declare Function BC_Busy(ByRef bc As BoardControl) As Boolean
