'' =====================================================================
'' BeginnerChess - gui.bi
'' A small "immediate mode" GUI: every frame the screen code calls
'' UI_Button(...) etc.; the call draws the widget and returns True when
'' it was clicked. Also: input polling, tooltips, modal dialogs.
'' =====================================================================
#pragma once
#include once "gfx.bi"

'' Key codes returned in UI.keyCode for special keys (fbgfx extended keys
'' arrive as Chr(255) + scan character).
Const KEY_ESCAPE    = 27
Const KEY_ENTER     = 13
Const KEY_BACKSPACE = 8
Const KEY_LEFT      = 1075
Const KEY_RIGHT     = 1077
Const KEY_UP        = 1072
Const KEY_DOWN      = 1080
Const KEY_F1        = 1059
Const KEY_CTRL_V    = 22
Const KEY_CTRL_C    = 3

Enum ButtonStyle
    BTN_NORMAL = 0      '' light button
    BTN_PRIMARY         '' blue, main action
    BTN_DANGER          '' red, e.g. Resign
    BTN_MENU            '' large main-menu button
End Enum

Type UIState
    mx            As Integer
    my            As Integer
    buttons       As Integer
    prevButtons   As Integer
    wheel         As Integer
    wheelDelta    As Integer
    pressed       As Boolean    '' left button went down this frame
    released      As Boolean    '' left button went up this frame
    down          As Boolean
    keyCode       As Integer    '' 0 = no key this frame
    keyChar       As String
    typed         As String     '' all printable characters typed this frame
    quitRequested As Boolean    '' window close button
    blockInput    As Boolean    '' True while a modal dialog covers the screen
    hotId         As String
    activeId      As String
    tooltipId     As String
    tooltipText   As String
    hoverId       As String
    hoverStart    As Double
    frameStart    As Double
    now           As Double
    fakeInput     As Boolean    '' input is set by code (automated screenshots)
    fastUntil     As Double     '' full frame rate until this time (else idle rate)
End Type

Extern UI As UIState

'' Keeps the full frame rate for a while (call during animations).
Declare Sub UI_KeepFast(ByVal seconds As Double = 0.3)
Declare Sub UI_BeginFrame()
Declare Sub UI_EndFrame()
'' True if the mouse is over the rectangle and input is not blocked.
Declare Function UI_Hover(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer) As Boolean
Declare Function UI_Button(ByRef id As Const String, ByVal x As Integer, ByVal y As Integer, _
                           ByVal w As Integer, ByVal h As Integer, ByRef label As Const String, _
                           ByVal enabled As Boolean = True, ByRef tooltip As Const String = "", _
                           ByVal style As Integer = BTN_NORMAL) As Boolean
'' "<  value  >" option chooser. options are separated by "|".
'' Returns True when the value changed.
Declare Function UI_Selector(ByRef id As Const String, ByVal x As Integer, ByVal y As Integer, _
                             ByVal w As Integer, ByVal h As Integer, ByRef options As Const String, _
                             ByRef index As Integer, ByVal enabled As Boolean = True, _
                             ByRef tooltip As Const String = "") As Boolean
'' Horizontal slider; returns True while the value changes.
Declare Function UI_Slider(ByRef id As Const String, ByVal x As Integer, ByVal y As Integer, _
                           ByVal w As Integer, ByVal h As Integer, ByRef value As Integer, _
                           ByVal minV As Integer, ByVal maxV As Integer, ByVal enabled As Boolean = True, _
                           ByRef tooltip As Const String = "") As Boolean
Declare Sub UI_SetTooltip(ByRef id As Const String, ByRef text As Const String)
Declare Sub UI_DrawBackground()
Declare Function UI_OptionCount(ByRef options As Const String) As Integer
Declare Function UI_OptionText(ByRef options As Const String, ByVal index As Integer) As String

'' ---- Notifications ("toasts") ----------------------------------------
'' Shows a small card at the top of the screen for a few seconds.
Declare Sub UI_ShowToast(ByRef title As Const String, ByRef text As Const String)
Declare Sub UI_ClearToasts()

'' ---- Modal dialog ---------------------------------------------------
Type DialogState
    active  As Boolean
    id      As String
    title   As String
    text    As String
    buttons As String      '' "Yes|No"
    opened  As Double
End Type

Declare Sub Dialog_Open(ByRef d As DialogState, ByRef id As Const String, ByRef title As Const String, _
                        ByRef text As Const String, ByRef buttons As Const String)
'' Draws the dialog. Returns the index of the clicked button (Esc = last
'' button, Enter = first), or -1 while still open. Closes on click.
Declare Function Dialog_Run(ByRef d As DialogState) As Integer

'' ---- Text input dialog ----------------------------------------------
Type InputDialogState
    active    As Boolean
    id        As String
    title     As String
    prompt    As String
    text      As String
    buttons   As String      '' e.g. "Start|Paste|Cancel"
    errorText As String      '' shown in red under the field
    maxLen    As Integer
    masked    As Boolean     '' password: show * instead of the characters
End Type

Declare Sub InputDialog_Open(ByRef d As InputDialogState, ByRef id As Const String, ByRef title As Const String, _
                             ByRef prompt As Const String, ByRef initial As Const String, ByRef buttons As Const String, _
                             ByVal maxLen As Integer = 120)
'' Returns the clicked button index (Enter = 0, Esc = last) or -1.
'' Unlike Dialog_Run the dialog stays open; the caller closes it by
'' setting d.active = False (so it can show an error instead).
Declare Function InputDialog_Run(ByRef d As InputDialogState) As Integer
'' Pastes the clipboard into the field (used by a "Paste" button).
Declare Sub InputDialog_Paste(ByRef d As InputDialogState)
'' Width a dialog needs for its buttons.
Declare Function Dialog_ButtonsWidth(ByRef buttons As Const String) As Integer
