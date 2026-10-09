'' =====================================================================
'' BeginnerChess - files.bas
'' The Save/Load screen (save slots and autosave) and the PGN import
'' screen (choose a file, then a game inside it).
'' =====================================================================
#include once "screens.bi"
#include once "dir.bi"
#include once "famous.bi"

'' ---------------------------------------------------------------------
'' Save / Load
'' ---------------------------------------------------------------------
Dim Shared SLMode As Integer
Dim Shared SLReturn As Integer
Dim Shared SLDlg As DialogState
Dim Shared SLPendingSlot As Integer
Dim Shared SLInfo(0 To SAVE_SLOTS) As SaveInfo
Dim Shared SLInfoTime As Double

Sub SaveLoad_Begin(ByVal mode As Integer, ByVal returnScreen As Integer)
    SLMode = mode
    SLReturn = returnScreen
    SLDlg.active = False
    SLInfoTime = 0
End Sub

Private Sub RefreshSlotInfo()
    Dim As Integer i
    For i = 0 To SAVE_SLOTS
        Save_ReadInfo(i, SLInfo(i))
    Next
    SLInfoTime = Timer
End Sub

Function SaveLoad_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_SAVELOAD
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    If SLInfoTime = 0 Then RefreshSlotInfo()
    UI.blockInput = SLDlg.active
    UI_DrawBackground()
    Screen_DrawHeader(IIf(SLMode = SLMODE_SAVE, "Save Game", "Load Game"))

    Dim As Integer pw = 860, px = (sw - pw) \ 2, py = 62
    Dim As Integer firstSlot = IIf(SLMode = SLMODE_SAVE, 1, 0)
    Dim As Integer rowH = 66, i
    Text_Draw(px, py, IIf(SLMode = SLMODE_SAVE, "Choose a slot for your game:", "Choose a game to continue:"), _
              24, RGB(240, 230, 210))
    Dim As Integer y = py + 40
    For i = firstSlot To SAVE_SLOTS
        Dim As ULong fill = IIf(SLInfo(i).exists, RGB(250, 246, 236), RGB(226, 228, 234))
        Gfx_Panel(px, y, pw, rowH - 8, 10, fill, RGB(140, 120, 90), False)
        Text_Draw(px + 16, y + 8, Save_SlotName(i), 22, RGB(80, 52, 24))
        If SLInfo(i).exists Then
            If SLInfo(i).valid Then
                Dim As String status = IIf(SLInfo(i).result = "*", "in progress", "finished " & SLInfo(i).result)
                Text_Draw(px + 150, y + 8, SLInfo(i).description, 20, RGB(40, 36, 30))
                Text_Draw(px + 150, y + 33, SLInfo(i).savedAt & "  -  " & ((SLInfo(i).moveCount + 1) \ 2) & _
                          " moves, " & status, 16, RGB(110, 100, 90))
            Else
                Text_Draw(px + 150, y + 16, "Damaged save: " & SLInfo(i).errorText, 18, RGB(180, 50, 30))
            End If
        Else
            Text_Draw(px + 150, y + 16, "- empty -", 20, RGB(140, 140, 150))
        End If

        Dim As Integer bx = px + pw - 140, by = y + 9
        If SLMode = SLMODE_SAVE Then
            If UI_Button("sl.save" & i, bx, by, 124, 40, "Save here", True, "Save the current game in " & _
                         Save_SlotName(i) & ".", BTN_PRIMARY) Then
                SLPendingSlot = i
                If SLInfo(i).exists Then
                    Dialog_Open(SLDlg, "overwrite", "Replace this save?", Save_SlotName(i) & _
                                " already contains a game. Replace it with the current game?", "Replace|Cancel")
                Else
                    Dim As String errMsg
                    If Play_SaveToSlot(i, errMsg) Then
                        Play_ShowMessage("Game saved in " & Save_SlotName(i) & ".")
                        nextScreen = SLReturn
                    Else
                        Dialog_Open(SLDlg, "error", "Could not save", errMsg, "OK")
                    End If
                End If
            End If
        Else
            Dim As Boolean canLoad = SLInfo(i).exists AndAlso SLInfo(i).valid
            If UI_Button("sl.load" & i, bx, by, 124, 40, "Load", canLoad, "Continue this game.", BTN_PRIMARY) Then
                Dim As String errMsg
                If Play_LoadFromSlot(i, errMsg) Then
                    nextScreen = SCREEN_PLAY
                Else
                    Dialog_Open(SLDlg, "error", "Could not load", errMsg, "OK")
                End If
            End If
            If i > 0 AndAlso SLInfo(i).exists Then
                If UI_Button("sl.del" & i, bx - 110, by, 100, 40, "Delete", True, "Delete this saved game.") Then
                    SLPendingSlot = i
                    Dialog_Open(SLDlg, "delete", "Delete?", "Delete the game in " & Save_SlotName(i) & _
                                "? This cannot be undone.", "Delete|Cancel")
                End If
            End If
        End If
        y += rowH
    Next

    Text_DrawWrapped(180, sh - 58, sw - 200, "Saved games are ordinary PGN files in: " & Save_Directory(), 16, RGB(160, 176, 200))
    Dim As Boolean goBack = UI_Button("sl.back", 20, sh - 64, 140, 46, "< Back", True, "Go back without saving or loading.")
    If UI.keyCode = KEY_ESCAPE AndAlso Not SLDlg.active Then goBack = True
    If goBack Then nextScreen = SLReturn

    If SLDlg.active Then
        Dim As Integer r = Dialog_Run(SLDlg)
        If r >= 0 Then
            Select Case SLDlg.id
            Case "overwrite"
                If r = 0 Then
                    Dim As String errMsg
                    If Play_SaveToSlot(SLPendingSlot, errMsg) Then
                        Play_ShowMessage("Game saved in " & Save_SlotName(SLPendingSlot) & ".")
                        nextScreen = SLReturn
                    Else
                        Dialog_Open(SLDlg, "error", "Could not save", errMsg, "OK")
                    End If
                End If
            Case "delete"
                If r = 0 Then Save_Delete(SLPendingSlot)
                RefreshSlotInfo()
            End Select
        End If
    End If
    If nextScreen <> SCREEN_SAVELOAD Then SLInfoTime = 0
    Return nextScreen
End Function

'' ---------------------------------------------------------------------
'' PGN import
'' ---------------------------------------------------------------------
Const IMPORT_MAX_FILES = 200
Const IMPORT_MAX_GAMES = 500

Dim Shared ImpReturn As Integer
Dim Shared ImpMode As Integer = 0
Dim Shared ImpFiles(0 To IMPORT_MAX_FILES - 1) As String
Dim Shared ImpFileCount As Integer
Dim Shared ImpGames() As String
Dim Shared ImpGameCount As Integer
Dim Shared ImpGameLabel(0 To IMPORT_MAX_GAMES - 1) As String
Dim Shared ImpChosenFile As String
Dim Shared ImpScroll As Integer
Dim Shared ImpDlg As DialogState
Dim Shared ImpDone As Boolean = False
Dim Shared ImpPick As Integer = -1

Private Sub ScanFolder(ByRef folder As Const String)
    Dim As String pattern(0 To 1) = {"*.pgn", "*.PGN"}
    Dim As Integer k
    For k = 0 To 1
        Dim As String f = Dir(folder & "/" & pattern(k), fbNormal)
        Do While f <> "" AndAlso ImpFileCount < IMPORT_MAX_FILES
            Dim As String full = folder & "/" & f
            Dim As Integer j, dup = 0
            For j = 0 To ImpFileCount - 1
                If ImpFiles(j) = full Then dup = 1
            Next
            If dup = 0 AndAlso LCase(f) <> "autosave.pgn" AndAlso Left(LCase(f), 4) <> "slot" Then
                ImpFiles(ImpFileCount) = full
                ImpFileCount += 1
            End If
            f = Dir()
        Loop
    Next
End Sub

Sub Import_Begin(ByVal returnScreen As Integer, ByVal mode As Integer = 0)
    ImpReturn = returnScreen
    ImpMode = mode
    ImpFileCount = 0
    ImpGameCount = 0
    ImpChosenFile = ""
    ImpScroll = 0
    ImpDlg.active = False
    ScanFolder(Save_Directory())
    ScanFolder(Profile_Dir())                     '' tournament_games.pgn
    ScanFolder(ExePath() & "/data/games")
End Sub

Private Function ShortName(ByRef full As Const String) As String
    Dim As Integer i
    For i = Len(full) To 1 Step -1
        If Mid(full, i, 1) = "/" OrElse Mid(full, i, 1) = "\" Then Return Mid(full, i + 1)
    Next
    Return full
End Function

Private Sub OpenPgnFile(ByRef fileName As Const String)
    Dim As String text
    If Not Pgn_ReadFile(fileName, text) Then
        Dialog_Open(ImpDlg, "error", "Could not open", "The file could not be read: " & fileName, "OK")
        Exit Sub
    End If
    ReDim ImpGames(0 To 15)
    ImpGameCount = Pgn_SplitGames(text, ImpGames())
    If ImpGameCount > IMPORT_MAX_GAMES Then ImpGameCount = IMPORT_MAX_GAMES
    If ImpGameCount = 0 Then
        Dialog_Open(ImpDlg, "error", "No games", "No chess games were found in " & ShortName(fileName) & ".", "OK")
        Exit Sub
    End If
    Dim As Integer i
    For i = 0 To ImpGameCount - 1
        Dim As PgnTags tags
        Pgn_ParseTags(ImpGames(i), tags)
        Dim As String yr = Left(Pgn_GetTag(tags, "Date", "????"), 4)
        ImpGameLabel(i) = Pgn_GetTag(tags, "White", "?") & " - " & Pgn_GetTag(tags, "Black", "?") & _
                          "  " & Pgn_GetTag(tags, "Result", "*") & IIf(yr <> "????" AndAlso yr <> "", "  (" & yr & ")", "")
    Next
    ImpChosenFile = fileName
    ImpScroll = 0
End Sub

Function Import_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_IMPORT
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    UI.blockInput = ImpDlg.active
    UI_DrawBackground()
    Screen_DrawHeader("Import PGN")

    Dim As Integer pw = 860, px = (sw - pw) \ 2, py = 62, rowH = 44
    Dim As Integer listTop = py + 44, visible = (sh - 90 - listTop) \ rowH
    Dim As Boolean choosingGame = (ImpChosenFile <> "")
    Dim As Integer count = IIf(choosingGame, ImpGameCount, ImpFileCount)

    If choosingGame Then
        Text_Draw(px, py, ShortName(ImpChosenFile) & ": choose a game (" & ImpGameCount & ")", 24, RGB(240, 230, 210))
    ElseIf ImpMode = 1 Then
        Text_Draw(px, py, "Choose a PGN file to add to your library:", 24, RGB(240, 230, 210))
    Else
        Text_Draw(px, py, "Choose a PGN file:", 24, RGB(240, 230, 210))
    End If

    If UI_Hover(px, listTop, pw, visible * rowH) AndAlso UI.wheelDelta <> 0 Then ImpScroll -= UI.wheelDelta * 3
    If ImpScroll > count - visible Then ImpScroll = count - visible
    If ImpScroll < 0 Then ImpScroll = 0

    If count = 0 Then
        Text_DrawWrapped(px, listTop + 10, pw, "No PGN files were found. Put .pgn files into " & _
                         Save_Directory() & " or " & ExePath() & "/data/games and they will appear here.", _
                         20, RGB(220, 220, 230))
    End If
    Dim As Integer i
    For i = ImpScroll To ImpScroll + visible - 1
        If i >= count Then Exit For
        Dim As Integer y = listTop + (i - ImpScroll) * rowH
        Dim As String label = IIf(choosingGame, (i + 1) & ".  " & ImpGameLabel(i), ShortName(ImpFiles(i)))
        If UI_Button("imp.row" & i, px, y, pw, rowH - 6, label, True, _
                     IIf(choosingGame, "Load this game.", ImpFiles(i)), BTN_MENU) Then
            If choosingGame Then
                ImpPick = i
                Dialog_Open(ImpDlg, "pick", "Open game", ImpGameLabel(i) & "|" & _
                            "Replay the game move by move, or continue playing from its last position?", _
                            "Replay|Play on|Cancel")
            ElseIf ImpMode = 1 Then
                '' Add every game of the file to the Famous Games library.
                Dim As Integer added, skipped
                Dim As String errMsg
                Famous_AddPgnFile(ImpFiles(i), added, skipped, errMsg)
                Dim As String msg = added & " game" & IIf(added = 1, "", "s") & " added to your library."
                If skipped > 0 Then msg &= " " & skipped & " skipped (already there or not readable)."
                If errMsg <> "" AndAlso added = 0 Then msg &= " " & errMsg
                Dialog_Open(ImpDlg, "added", "Library", msg, "OK")
                ImpDone = True
            Else
                OpenPgnFile(ImpFiles(i))
            End If
        End If
    Next
    If count > visible Then
        Text_Draw(px + pw - 220, sh - 52, "Scroll with the mouse wheel", 16, RGB(160, 176, 200))
    End If

    Dim As Boolean back = UI_Button("imp.back", 20, sh - 64, 140, 46, "< Back", True, "Go back.")
    If UI.keyCode = KEY_ESCAPE AndAlso Not ImpDlg.active Then back = True
    If back Then
        If choosingGame Then
            ImpChosenFile = ""
            ImpScroll = 0
        Else
            nextScreen = ImpReturn
        End If
    End If

    If ImpDlg.active Then
        Dim As String dlgId = ImpDlg.id
        Dim As Integer r = Dialog_Run(ImpDlg)
        If r >= 0 AndAlso dlgId = "pick" AndAlso ImpPick >= 0 AndAlso r < 2 Then
            Dim As String errMsg
            Dim As Boolean ok
            If r = 0 Then
                ok = Viewer_StartPgn(ImpGames(ImpPick), SCREEN_IMPORT, errMsg)
                If ok Then nextScreen = SCREEN_VIEWER
            Else
                ok = Play_StartFromPGN(NewGameOpts, ImpGames(ImpPick), errMsg)
                If ok Then nextScreen = SCREEN_PLAY
            End If
            If Not ok Then Dialog_Open(ImpDlg, "error", "Could not import", "Game " & (ImpPick + 1) & ": " & errMsg, "OK")
        ElseIf r >= 0 AndAlso ImpDone Then
            ImpDone = False
            nextScreen = ImpReturn
        End If
    End If
    Return nextScreen
End Function
