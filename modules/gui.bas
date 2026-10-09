'' =====================================================================
'' BeginnerChess - gui.bas
'' Immediate-mode widgets. See gui.bi.
'' =====================================================================
#include once "gui.bi"
#include once "clipboard.bi"
#include once "audio.bi"

Dim Shared UI As UIState

Const TOOLTIP_DELAY = 0.55
Dim Shared PendingDown As Boolean = False
Dim Shared PendingRelease As Boolean = False
Const FRAME_TIME = 1.0 / 60
Const IDLE_FRAME_TIME = 1.0 / 20       '' when nothing happens: save the battery
Const SLEEP_FRAME_TIME = 1.0 / 10      '' nothing happened for a few seconds

Sub UI_KeepFast(ByVal seconds As Double = 0.3)
    If UI.fastUntil < Timer + seconds Then UI.fastUntil = Timer + seconds
End Sub

'' ---------------------------------------------------------------------
'' Frame handling and input
'' ---------------------------------------------------------------------
'' Keys are queued so that none is lost when several arrive within one
'' frame (fast typing while the program draws slowly): each frame takes
'' exactly one key from the queue, in order (UI.keyCode, and UI.typed for
'' printable characters). While keys are waiting the frame rate stays high.
Const KEYQ_SIZE = 64
Dim Shared KeyQAscii(0 To KEYQ_SIZE - 1) As Integer
Dim Shared KeyQScan(0 To KEYQ_SIZE - 1) As Integer
Dim Shared KeyQHead As Integer, KeyQCount As Integer

Private Sub TakeKeys()
    If KeyQCount = 0 Then Exit Sub
    Dim As Integer a = KeyQAscii(KeyQHead), sc = KeyQScan(KeyQHead)
    KeyQHead = (KeyQHead + 1) Mod KEYQ_SIZE
    KeyQCount -= 1
    If a >= 32 AndAlso a < 127 Then UI.typed = Chr(a)
    If a > 0 AndAlso a < 255 Then
        UI.keyCode = a
        UI.keyChar = Chr(a)
    Else
        UI.keyCode = 1000 + sc
    End If
    If KeyQCount > 0 Then UI_KeepFast(0.5)                         '' deliver the rest promptly
End Sub

Sub UI_BeginFrame()
    UI.frameStart = Timer
    UI.now = UI.frameStart
    UI.prevButtons = UI.buttons
    UI.keyCode = 0
    UI.keyChar = ""
    UI.typed = ""

    If Not UI.fakeInput Then
        '' Events are used (rather than polling the button state) so that a
        '' very quick click - down and up within one frame - is never lost.
        Dim As Boolean wasDown = PendingDown
        Dim As Boolean gotPress = False, gotRelease = False
        If PendingRelease Then
            '' A click that was pressed and released during the last frame.
            gotRelease = True
            wasDown = False
            PendingRelease = False
        End If
        UI.wheelDelta = 0
        Dim As FB.EVENT ev
        Do While ScreenEvent(@ev)
            UI_KeepFast(1.5)                    '' any input: run smoothly for a while
            Select Case ev.type
            Case FB.EVENT_MOUSE_MOVE
                UI.mx = ev.x : UI.my = ev.y
            Case FB.EVENT_MOUSE_BUTTON_PRESS
                If ev.button = FB.BUTTON_LEFT Then
                    gotPress = True
                    wasDown = True
                End If
            Case FB.EVENT_MOUSE_BUTTON_RELEASE
                If ev.button = FB.BUTTON_LEFT Then
                    If gotPress Then
                        PendingRelease = True       '' deliver next frame
                    Else
                        gotRelease = True
                        wasDown = False
                    End If
                End If
            Case FB.EVENT_MOUSE_WHEEL
                UI.wheelDelta += ev.z - UI.wheel
                UI.wheel = ev.z
            Case FB.EVENT_MOUSE_EXIT
                UI.mx = -1 : UI.my = -1
            Case FB.EVENT_KEY_PRESS, FB.EVENT_KEY_REPEAT
                If KeyQCount < KEYQ_SIZE Then                    '' handled in order below
                    KeyQAscii((KeyQHead + KeyQCount) Mod KEYQ_SIZE) = ev.ascii
                    KeyQScan((KeyQHead + KeyQCount) Mod KEYQ_SIZE) = ev.scancode
                    KeyQCount += 1
                End If
            Case FB.EVENT_WINDOW_CLOSE
                UI.quitRequested = True
            End Select
        Loop
        Do While Len(InKey()) > 0      '' keep the keyboard buffer empty
        Loop
        TakeKeys()
        Dim As Long mx, my
        If GetMouse(mx, my) = 0 Then UI.mx = mx : UI.my = my
        PendingDown = wasDown
        UI.buttons = IIf(wasDown, 1, 0)
        '' Ensure the press/release edges are reported exactly once.
        If gotPress Then UI.prevButtons = 0
        If gotRelease AndAlso Not gotPress Then UI.prevButtons = 1 : UI.buttons = 0
    End If

    UI.down = (UI.buttons And 1) <> 0
    UI.pressed = UI.down AndAlso (UI.prevButtons And 1) = 0
    UI.released = (Not UI.down) AndAlso (UI.prevButtons And 1) <> 0
    UI.blockInput = False
    UI.hotId = ""
    UI.tooltipId = ""
    UI.tooltipText = ""
End Sub

Private Sub DrawTooltip()
    If UI.tooltipText = "" Then
        UI.hoverId = ""
        Exit Sub
    End If
    If UI.tooltipId <> UI.hoverId Then
        UI.hoverId = UI.tooltipId
        UI.hoverStart = UI.now
        Exit Sub
    End If
    If UI.now - UI.hoverStart < TOOLTIP_DELAY AndAlso Not UI.fakeInput Then Exit Sub

    Dim As Integer ts = 18
    Dim As String lines()
    ReDim lines(0 To 7)
    Dim As Integer n = Text_Wrap(UI.tooltipText, ts, 360, lines()), i, w = 0
    For i = 0 To n - 1
        If Text_Width(lines(i), ts) > w Then w = Text_Width(lines(i), ts)
    Next
    Dim As Integer bw = w + 20, bh = n * (ts + 4) + 14
    Dim As Integer x = UI.mx + 16, y = UI.my + 22
    If x + bw > Gfx_Width() - 4 Then x = Gfx_Width() - 4 - bw
    If y + bh > Gfx_Height() - 4 Then y = UI.my - bh - 8
    If x < 4 Then x = 4
    Gfx_Panel(x, y, bw, bh, 8, RGB(255, 252, 225), RGB(120, 110, 70))
    For i = 0 To n - 1
        Text_Draw(x + 10, y + 8 + i * (ts + 4), lines(i), ts, RGB(40, 35, 20))
    Next
End Sub

'' ---------------------------------------------------------------------
'' Toasts
'' ---------------------------------------------------------------------
Type ToastItem
    title As String
    text  As String
    start As Double
End Type
Dim Shared Toasts(0 To 7) As ToastItem
Dim Shared ToastCount As Integer = 0
Const TOAST_SECONDS = 4.5

Sub UI_ShowToast(ByRef title As Const String, ByRef text As Const String)
    If ToastCount >= 8 Then Exit Sub
    Toasts(ToastCount).title = title
    Toasts(ToastCount).text = text
    Toasts(ToastCount).start = 0             '' starts when it reaches the front
    ToastCount += 1
End Sub

Sub UI_ClearToasts()
    ToastCount = 0
End Sub

Private Sub DrawToasts()
    If ToastCount = 0 Then Exit Sub
    '' One at a time, the oldest first.
    If Toasts(0).start = 0 Then Toasts(0).start = Timer
    Dim As Double age = Timer - Toasts(0).start
    If age > TOAST_SECONDS Then
        Dim As Integer i
        For i = 1 To ToastCount - 1
            Toasts(i - 1) = Toasts(i)
        Next
        ToastCount -= 1
        Exit Sub
    End If
    UI_KeepFast(0.2)
    Dim As Integer w = 440, h = 74
    Dim As Integer x = (Gfx_Width() - w) \ 2
    Dim As Single slide = IIf(age < 0.3, age / 0.3, IIf(age > TOAST_SECONDS - 0.3, (TOAST_SECONDS - age) / 0.3, 1))
    Dim As Integer y = -h + CInt((h + 58) * slide)
    Gfx_Panel(x, y, w, h, 14, RGB(255, 248, 220), RGB(200, 150, 30))
    Gfx_FillCircle(x + 40, y + h \ 2, 22, RGB(230, 170, 30))
    Gfx_FillCircle(x + 40, y + h \ 2, 16, RGB(255, 215, 80))
    Text_DrawCentered(x + 40, y + h \ 2 - 11, "*", 22, RGB(150, 90, 10))
    Text_Draw(x + 74, y + 10, Toasts(0).title, 16, RGB(150, 100, 20))
    Text_Draw(x + 74, y + 32, Left(Toasts(0).text, 30), 24, RGB(70, 46, 22))
End Sub

Sub UI_EndFrame()
    DrawToasts()
    DrawTooltip()
    If UI.released Then UI.activeId = ""
    Gfx_Present()
    If Not UI.fakeInput Then
        '' Limit to ~60 frames per second without busy-waiting. When idle,
        '' draw less often, but wake up at once when input arrives.
        Dim As Double now = Timer
        Dim As Double target = FRAME_TIME
        If now >= UI.fastUntil + 3 Then
            target = SLEEP_FRAME_TIME
        ElseIf now >= UI.fastUntil Then
            target = IDLE_FRAME_TIME
        End If
        Dim As Double wakeAt = UI.frameStart + target
        If target = FRAME_TIME Then
            Dim As Integer ms = (wakeAt - now) * 1000
            If ms < 1 Then ms = 1
            Sleep ms, 1
        Else
            Sleep 1, 1
            Do While Timer < wakeAt
                If ScreenEvent(0) Then Exit Do      '' peek only: the event stays queued
                Sleep 8, 1
            Loop
        End If
    End If
End Sub

Function UI_Hover(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer) As Boolean
    If UI.blockInput Then Return False
    Return UI.mx >= x AndAlso UI.mx < x + w AndAlso UI.my >= y AndAlso UI.my < y + h
End Function

Sub UI_SetTooltip(ByRef id As Const String, ByRef text As Const String)
    UI.tooltipId = id
    UI.tooltipText = text
End Sub

Sub UI_DrawBackground()
    Gfx_GradientRect(0, 0, Gfx_Width(), Gfx_Height(), RGB(44, 72, 108), RGB(22, 34, 54))
End Sub

'' ---------------------------------------------------------------------
'' Widgets
'' ---------------------------------------------------------------------
Function UI_Button(ByRef id As Const String, ByVal x As Integer, ByVal y As Integer, _
                   ByVal w As Integer, ByVal h As Integer, ByRef label As Const String, _
                   ByVal enabled As Boolean = True, ByRef tooltip As Const String = "", _
                   ByVal style As Integer = BTN_NORMAL) As Boolean
    Dim As Boolean hover = UI_Hover(x, y, w, h)
    Dim As Boolean clicked = False
    If hover Then
        UI.hotId = id
        If tooltip <> "" Then UI_SetTooltip(id, tooltip)
        If enabled Then
            If UI.pressed Then UI.activeId = id
            If UI.released AndAlso UI.activeId = id Then
                clicked = True
                Audio_Play(SND_CLICK)
            End If
        End If
    End If
    Dim As Boolean held = enabled AndAlso hover AndAlso UI.down AndAlso UI.activeId = id

    Dim As ULong fill, border, txt
    Select Case style
    Case BTN_PRIMARY
        fill = RGB(52, 120, 206) : border = RGB(28, 70, 140) : txt = RGB(255, 255, 255)
    Case BTN_DANGER
        fill = RGB(206, 70, 60) : border = RGB(130, 36, 30) : txt = RGB(255, 255, 255)
    Case BTN_MENU
        fill = RGB(250, 244, 228) : border = RGB(150, 112, 70) : txt = RGB(70, 46, 22)
    Case Else
        fill = RGB(244, 244, 248) : border = RGB(140, 146, 160) : txt = RGB(36, 40, 52)
    End Select
    If Not enabled Then
        fill = Color_Mix(fill, RGB(150, 150, 155), 0.55)
        border = Color_Mix(border, RGB(120, 120, 125), 0.6)
        txt = Color_Mix(txt, RGB(110, 110, 115), 0.6)
    ElseIf held Then
        fill = Color_Shade(fill, 0.86)
    ElseIf hover Then
        fill = Color_Mix(fill, RGB(255, 255, 255), 0.22)
        If style = BTN_MENU Then fill = RGB(255, 236, 170)
    End If

    Dim As Integer off = IIf(held, 2, 0)
    Gfx_Panel(x, y + off, w, h, h \ 4, fill, border, Not held)
    Dim As Integer ts = h * 0.46
    If ts > 30 Then ts = 30
    '' Shrink the text if it does not fit.
    Do While ts > 12 AndAlso Text_Width(label, ts) > w - 16
        ts -= 2
    Loop
    Text_DrawCentered(x + w \ 2, y + off + (h - ts) \ 2 + 1, label, ts, txt)
    Return clicked
End Function

Function UI_Slider(ByRef id As Const String, ByVal x As Integer, ByVal y As Integer, _
                   ByVal w As Integer, ByVal h As Integer, ByRef value As Integer, _
                   ByVal minV As Integer, ByVal maxV As Integer, ByVal enabled As Boolean = True, _
                   ByRef tooltip As Const String = "") As Boolean
    Dim As Boolean hover = UI_Hover(x, y, w, h), changed = False
    If hover AndAlso tooltip <> "" Then UI_SetTooltip(id, tooltip)
    If enabled AndAlso hover AndAlso UI.pressed Then UI.activeId = id
    Dim As Integer knobR = h \ 2 - 2
    Dim As Integer x0 = x + knobR + 2, x1 = x + w - knobR - 2
    Dim As Boolean dragging = enabled AndAlso UI.down AndAlso (Not UI.blockInput)
    If UI.activeId <> id Then dragging = False
    If dragging Then
        Dim As Integer nv = minV + CInt((UI.mx - x0) * (maxV - minV) / IIf(x1 > x0, x1 - x0, 1))
        If nv < minV Then nv = minV
        If nv > maxV Then nv = maxV
        If nv <> value Then value = nv : changed = True
    End If
    Dim As Integer cy = y + h \ 2
    Dim As Single fraction = (value - minV) / IIf(maxV > minV, maxV - minV, 1)
    Dim As Integer kx = x0 + (x1 - x0) * fraction
    Gfx_RoundRect(x0, cy - 4, x1 - x0, 8, 4, IIf(enabled, RGB(200, 204, 214), RGB(190, 190, 195)))
    Gfx_RoundRect(x0, cy - 4, kx - x0, 8, 4, IIf(enabled, RGB(52, 120, 206), RGB(160, 160, 165)))
    Gfx_FillCircle(kx, cy, knobR, RGB(90, 90, 100))
    Gfx_FillCircle(kx, cy, knobR - 2, IIf(enabled, IIf(UI.activeId = id OrElse hover, RGB(255, 236, 170), RGB(255, 255, 255)), RGB(220, 220, 220)))
    Return changed
End Function

Function UI_OptionCount(ByRef options As Const String) As Integer
    Dim As Integer n = 1, i
    For i = 1 To Len(options)
        If Mid(options, i, 1) = "|" Then n += 1
    Next
    Return n
End Function

Function UI_OptionText(ByRef options As Const String, ByVal index As Integer) As String
    Dim As Integer n = 0, i, start = 1
    For i = 1 To Len(options) + 1
        If i > Len(options) OrElse Mid(options, i, 1) = "|" Then
            If n = index Then Return Mid(options, start, i - start)
            n += 1
            start = i + 1
        End If
    Next
    Return ""
End Function

Function UI_Selector(ByRef id As Const String, ByVal x As Integer, ByVal y As Integer, _
                     ByVal w As Integer, ByVal h As Integer, ByRef options As Const String, _
                     ByRef index As Integer, ByVal enabled As Boolean = True, _
                     ByRef tooltip As Const String = "") As Boolean
    Dim As Integer n = UI_OptionCount(options)
    Dim As Boolean changed = False
    If UI_Button(id & ".prev", x, y, h, h, "<", enabled, tooltip) Then
        index = (index + n - 1) Mod n
        changed = True
    End If
    If UI_Button(id & ".next", x + w - h, y, h, h, ">", enabled, tooltip) Then
        index = (index + 1) Mod n
        changed = True
    End If
    Dim As ULong fill = IIf(enabled, RGB(255, 255, 255), RGB(200, 200, 205))
    Gfx_Panel(x + h + 6, y, w - 2 * h - 12, h, 8, fill, RGB(140, 146, 160), False)
    If UI_Hover(x + h + 6, y, w - 2 * h - 12, h) AndAlso tooltip <> "" Then UI_SetTooltip(id, tooltip)
    Dim As Integer ts = h * 0.48
    If ts > 26 Then ts = 26
    Text_DrawCentered(x + w \ 2, y + (h - ts) \ 2 + 1, UI_OptionText(options, index), ts, _
                      IIf(enabled, RGB(30, 40, 60), RGB(120, 120, 125)))
    Return changed
End Function

'' ---------------------------------------------------------------------
'' Dialogs
'' ---------------------------------------------------------------------
Sub Dialog_Open(ByRef d As DialogState, ByRef id As Const String, ByRef title As Const String, _
                ByRef text As Const String, ByRef buttons As Const String)
    d.active = True
    d.id = id
    d.title = title
    d.text = text
    d.buttons = buttons
    d.opened = Timer
    UI.activeId = ""          '' the click that opened it must not hit a dialog button
End Sub

Private Function ButtonWidth(ByRef label As Const String) As Integer
    Dim As Integer w = Text_Width(label, 22) + 40
    Return IIf(w < 150, 150, w)
End Function

Function Dialog_ButtonsWidth(ByRef buttons As Const String) As Integer
    Dim As Integer i, nb = UI_OptionCount(buttons), total = 0
    For i = 0 To nb - 1
        total += ButtonWidth(UI_OptionText(buttons, i))
    Next
    Return total + (nb - 1) * 18
End Function

Function Dialog_Run(ByRef d As DialogState) As Integer
    If Not d.active Then Return -1
    UI.blockInput = False
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    Gfx_FillRect(0, 0, sw, sh, RGBA(0, 0, 0, 120))

    Dim As Integer w = 560, ts = 22
    If Dialog_ButtonsWidth(d.buttons) + 60 > w Then w = Dialog_ButtonsWidth(d.buttons) + 60
    Dim As String lines()
    ReDim lines(0 To 15)
    Dim As Integer n = Text_Wrap(d.text, ts, w - 60, lines())
    Dim As Integer h = 90 + n * (ts + 6) + 80
    Dim As Integer x = (sw - w) \ 2, y = (sh - h) \ 2
    Gfx_Panel(x, y, w, h, 16, RGB(252, 248, 238), RGB(110, 84, 50))
    Gfx_RoundRect(x + 2, y + 2, w - 4, 56, 14, RGB(110, 84, 50))
    Gfx_FillRect(x + 2, y + 40, w - 4, 18, RGB(110, 84, 50))
    Text_DrawCentered(x + w \ 2, y + 15, d.title, 28, RGB(255, 246, 220))
    Dim As Integer i
    For i = 0 To n - 1
        Text_DrawCentered(x + w \ 2, y + 78 + i * (ts + 6), lines(i), ts, RGB(40, 34, 26))
    Next

    Dim As Integer nb = UI_OptionCount(d.buttons), bw = 150, bh = 48, gap = 18
    Dim As Integer total = Dialog_ButtonsWidth(d.buttons)
    Dim As Integer bx = x + (w - total) \ 2, by = y + h - bh - 20
    Dim As Integer result = -1
    For i = 0 To nb - 1
        If UI_Button(d.id & ".btn" & i, bx, by, ButtonWidth(UI_OptionText(d.buttons, i)), bh, _
                     UI_OptionText(d.buttons, i), True, "", IIf(i = 0, BTN_PRIMARY, BTN_NORMAL)) Then result = i
        bx += ButtonWidth(UI_OptionText(d.buttons, i)) + gap
    Next
    If UI.keyCode = KEY_ESCAPE Then result = nb - 1
    If UI.keyCode = KEY_ENTER Then result = 0
    '' The key is used up: a dialog opened in reaction must not see it too.
    If UI.keyCode = KEY_ESCAPE OrElse UI.keyCode = KEY_ENTER Then UI.keyCode = 0
    If result >= 0 Then d.active = False
    Return result
End Function

'' ---------------------------------------------------------------------
'' Text input dialog
'' ---------------------------------------------------------------------
Sub InputDialog_Open(ByRef d As InputDialogState, ByRef id As Const String, ByRef title As Const String, _
                     ByRef prompt As Const String, ByRef initial As Const String, ByRef buttons As Const String, _
                     ByVal maxLen As Integer = 120)
    d.active = True
    d.id = id
    d.title = title
    d.prompt = prompt
    d.text = initial
    d.buttons = buttons
    d.errorText = ""
    d.maxLen = maxLen
    d.masked = False                 '' set to True after opening for passwords
    UI.activeId = ""
End Sub

Sub InputDialog_Paste(ByRef d As InputDialogState)
    Dim As String clip
    If Clipboard_GetText(clip) Then
        '' Keep the first line only, without control characters.
        Dim As Integer nl = InStr(clip, Chr(10))
        If nl > 0 Then clip = Left(clip, nl - 1)
        clip = Trim(clip, Any " " & Chr(9, 13))
        d.text = Left(clip, d.maxLen)
        d.errorText = ""
    Else
        d.errorText = "Nothing could be pasted (no clipboard tool found). Please type the text instead."
    End If
End Sub

Function InputDialog_Run(ByRef d As InputDialogState) As Integer
    If Not d.active Then Return -1
    UI.blockInput = False
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    Gfx_FillRect(0, 0, sw, sh, RGBA(0, 0, 0, 120))

    Dim As Integer w = 820, h = 300
    If Dialog_ButtonsWidth(d.buttons) + 60 > w Then w = Dialog_ButtonsWidth(d.buttons) + 60
    Dim As Integer x = (sw - w) \ 2, y = (sh - h) \ 2
    Gfx_Panel(x, y, w, h, 16, RGB(252, 248, 238), RGB(110, 84, 50))
    Gfx_RoundRect(x + 2, y + 2, w - 4, 56, 14, RGB(110, 84, 50))
    Gfx_FillRect(x + 2, y + 40, w - 4, 18, RGB(110, 84, 50))
    Text_DrawCentered(x + w \ 2, y + 15, d.title, 28, RGB(255, 246, 220))
    Text_DrawWrapped(x + 30, y + 72, w - 60, d.prompt, 18, RGB(50, 44, 36))

    '' Editing: typed characters, Backspace, Ctrl+V.
    If Len(UI.typed) > 0 Then
        d.text = Left(d.text & UI.typed, d.maxLen)
        d.errorText = ""
    End If
    If UI.keyCode = KEY_BACKSPACE AndAlso Len(d.text) > 0 Then d.text = Left(d.text, Len(d.text) - 1)
    If UI.keyCode = KEY_CTRL_V Then InputDialog_Paste(d)

    '' The text field (shows the end of long text).
    Dim As Integer fx = x + 30, fy = y + 128, fw = w - 60, fh = 44, ts = 20
    Gfx_Panel(fx, fy, fw, fh, 8, RGB(255, 255, 255), RGB(52, 120, 206), False)
    Dim As Integer maxChars = (fw - 24) \ (ts \ 2)
    Dim As String shown = IIf(d.masked, String(Len(d.text), "*"), d.text)
    If Len(shown) > maxChars - 1 Then shown = Right(shown, maxChars - 1)
    Text_Draw(fx + 12, fy + (fh - ts) \ 2, shown, ts, RGB(20, 24, 32))
    If (Int(Timer * 2) Mod 2) = 0 Then
        Dim As Integer cx = fx + 12 + Text_Width(shown, ts)
        Gfx_FillRect(cx + 1, fy + 9, 2, fh - 18, RGB(20, 24, 32))
    End If
    If d.errorText <> "" Then Text_DrawWrapped(fx, fy + fh + 8, fw, d.errorText, 18, RGB(190, 40, 30))

    Dim As Integer nb = UI_OptionCount(d.buttons), bh = 48, i, result = -1
    Dim As Integer bx = x + (w - Dialog_ButtonsWidth(d.buttons)) \ 2, by = y + h - bh - 18
    For i = 0 To nb - 1
        Dim As String label = UI_OptionText(d.buttons, i)
        If UI_Button(d.id & ".btn" & i, bx, by, ButtonWidth(label), bh, label, True, "", _
                     IIf(i = 0, BTN_PRIMARY, BTN_NORMAL)) Then result = i
        bx += ButtonWidth(label) + 18
    Next
    If UI.keyCode = KEY_ESCAPE Then result = nb - 1
    If UI.keyCode = KEY_ENTER Then result = 0
    '' The key is used up: a dialog opened in reaction must not see it too.
    If UI.keyCode = KEY_ESCAPE OrElse UI.keyCode = KEY_ENTER Then UI.keyCode = 0
    Return result
End Function
