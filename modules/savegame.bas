'' =====================================================================
'' BeginnerChess - savegame.bas
'' See savegame.bi.
'' =====================================================================
#include once "savegame.bi"
#include once "engine.bi"
#include once "file.bi"
#include once "dir.bi"

Dim Shared SaveDir As String

Sub Save_SetDirectory(ByRef path As Const String)
    SaveDir = path
End Sub

Function Save_Directory() As String
    If SaveDir = "" Then SaveDir = ExePath() & "/saves"
    Return SaveDir
End Function

Function Save_EnsureDirectory() As Boolean
    Dim As String d = Save_Directory()
    If Dir(d, fbDirectory) <> "" Then Return True
    MkDir d
    Return Dir(d, fbDirectory) <> ""
End Function

Function Save_SlotFile(ByVal slot As Integer) As String
    If slot = 0 Then Return Save_Directory() & "/autosave.pgn"
    Return Save_Directory() & "/slot" & slot & ".pgn"
End Function

Function Save_SlotName(ByVal slot As Integer) As String
    If slot = 0 Then Return "Autosave"
    Return "Slot " & slot
End Function

Function Save_PlayerName(ByRef setup As SaveSetup, ByVal side As Integer) As String
    If setup.opponent = 0 Then Return IIf(side = SIDE_WHITE, "White player", "Black player")
    If side = setup.humanSide Then Return "Player"
    Return "Computer (" & Engine_LevelName(setup.difficulty) & ", " & Engine_StyleName(setup.style) & ")"
End Function

Function Save_Write(ByVal slot As Integer, ByRef g As ChessGame, ByRef setup As SaveSetup, _
                    ByRef errMsg As String) As Boolean
    errMsg = ""
    If slot < 0 OrElse slot > SAVE_SLOTS Then
        errMsg = "There is no save slot " & slot & "."
        Return False
    End If
    If Not Save_EnsureDirectory() Then
        errMsg = "The folder for saved games could not be created: " & Save_Directory()
        Return False
    End If
    Dim As PgnTags tags
    Pgn_SetTag(tags, "Event", IIf(setup.opponent = 0, "Two-player game", "Game against the computer"))
    Pgn_SetTag(tags, "Site", "Beginner Chess")
    Pgn_SetTag(tags, "Date", Pgn_Today())
    Pgn_SetTag(tags, "Round", "-")
    Pgn_SetTag(tags, "White", Save_PlayerName(setup, SIDE_WHITE))
    Pgn_SetTag(tags, "Black", Save_PlayerName(setup, SIDE_BLACK))
    Pgn_SetTag(tags, "CMVersion", CM_VERSION)
    Pgn_SetTag(tags, "CMOpponent", Str(setup.opponent))
    Pgn_SetTag(tags, "CMPlayAs", Str(setup.playAs))
    Pgn_SetTag(tags, "CMLevel", Str(setup.difficulty))
    Pgn_SetTag(tags, "CMStyle", Str(setup.style))
    Pgn_SetTag(tags, "CMHumanSide", IIf(setup.humanSide = SIDE_WHITE, "w", "b"))
    Pgn_SetTag(tags, "CMFlipped", IIf(setup.flipped, "1", "0"))
    If setup.practice Then Pgn_SetTag(tags, "CMPractice", "1")
    Pgn_SetTag(tags, "CMTermination", Str(CInt(g.termination)))
    Pgn_SetTag(tags, "CMSavedAt", Pgn_Today() & " " & Left(Time(), 5))
    Pgn_SetTag(tags, "CMFEN", Pos_GetFEN(g.pos))

    '' Write to a temporary file first so a failure never destroys the old save.
    Dim As String target = Save_SlotFile(slot), tmp = target & ".tmp"
    If Not Pgn_WriteFile(tmp, Pgn_Export(g, tags)) Then
        errMsg = "The game could not be written to " & tmp
        Return False
    End If
    If FileExists(target) Then Kill target
    If Name(tmp, target) <> 0 Then
        errMsg = "The save file could not be renamed to " & target
        Return False
    End If
    Return True
End Function

Private Function ClampInt(ByVal v As Integer, ByVal lo As Integer, ByVal hi As Integer) As Integer
    If v < lo Then Return lo
    If v > hi Then Return hi
    Return v
End Function

Function Save_Read(ByVal slot As Integer, ByRef g As ChessGame, ByRef setup As SaveSetup, _
                   ByRef errMsg As String) As Boolean
    errMsg = ""
    Dim As String fileName = Save_SlotFile(slot), text
    If Not FileExists(fileName) Then
        errMsg = Save_SlotName(slot) & " is empty."
        Return False
    End If
    If Not Pgn_ReadFile(fileName, text) Then
        errMsg = "The save file could not be opened: " & fileName
        Return False
    End If
    Dim As String games()
    ReDim games(0 To 1)
    If Pgn_SplitGames(text, games()) < 1 Then
        errMsg = "The save file is empty or damaged."
        Return False
    End If
    Dim As PgnTags tags
    Dim As String why
    If Not Pgn_ParseGame(games(0), g, tags, why) Then
        errMsg = "The save file is damaged. " & why
        Return False
    End If
    Dim As String expected = Pgn_GetTag(tags, "CMFEN")
    If expected <> "" AndAlso expected <> Pos_GetFEN(g.pos) Then
        errMsg = "The save file is damaged: the moves do not lead to the saved position."
        Return False
    End If

    setup.opponent = ClampInt(ValInt(Pgn_GetTag(tags, "CMOpponent", "0")), 0, 1)
    setup.playAs = ClampInt(ValInt(Pgn_GetTag(tags, "CMPlayAs", "0")), 0, 2)
    setup.difficulty = ClampInt(ValInt(Pgn_GetTag(tags, "CMLevel", "2")), 0, LEVEL_COUNT - 1)
    setup.style = ClampInt(ValInt(Pgn_GetTag(tags, "CMStyle", "0")), 0, STYLE_COUNT - 1)
    setup.humanSide = IIf(Pgn_GetTag(tags, "CMHumanSide", "w") = "b", SIDE_BLACK, SIDE_WHITE)
    setup.flipped = (Pgn_GetTag(tags, "CMFlipped", "0") = "1")
    setup.practice = (Pgn_GetTag(tags, "CMPractice", "0") = "1")

    '' Restore exactly how a finished game ended (claim, agreement, ...).
    Dim As Integer term = ValInt(Pgn_GetTag(tags, "CMTermination", "0"))
    If Game_IsOver(g) AndAlso term > TERM_NONE AndAlso term <= TERM_SEVENTY_FIVE_MOVE Then
        Select Case term
        Case TERM_AGREEMENT, TERM_THREEFOLD, TERM_FIFTY_MOVE
            If g.result = RESULT_DRAW Then g.termination = term
        Case TERM_RESIGNATION
            If g.result <> RESULT_DRAW Then g.termination = term
        End Select
    End If
    Return True
End Function

Function Save_ReadInfo(ByVal slot As Integer, ByRef info As SaveInfo) As Boolean
    info.exists = False : info.valid = False
    info.description = "" : info.savedAt = "" : info.moveCount = 0
    info.result = "" : info.errorText = ""
    Dim As String fileName = Save_SlotFile(slot), text
    If Not FileExists(fileName) Then Return False
    info.exists = True
    If Not Pgn_ReadFile(fileName, text) Then
        info.errorText = "Cannot open the file."
        Return True
    End If
    Dim As String games()
    ReDim games(0 To 1)
    If Pgn_SplitGames(text, games()) < 1 Then
        info.errorText = "Damaged file."
        Return True
    End If
    Dim As PgnTags tags
    Pgn_ParseTags(games(0), tags)
    info.valid = True
    If Pgn_GetTag(tags, "CMOpponent", "0") = "1" Then
        info.description = IIf(Pgn_GetTag(tags, "CMPractice", "0") = "1", "Practice: ", "") & "You (" & IIf(Pgn_GetTag(tags, "CMHumanSide", "w") = "b", "Black", "White") & _
                           ") vs Computer - " & Engine_LevelName(ClampInt(ValInt(Pgn_GetTag(tags, "CMLevel", "2")), 0, 4))
    Else
        info.description = Pgn_GetTag(tags, "White", "?") & " vs " & Pgn_GetTag(tags, "Black", "?")
    End If
    info.savedAt = Pgn_GetTag(tags, "CMSavedAt", Pgn_GetTag(tags, "Date", ""))
    info.moveCount = ValInt(Pgn_GetTag(tags, "PlyCount", "0"))
    info.result = Pgn_GetTag(tags, "Result", "*")
    Return True
End Function

Function Save_Delete(ByVal slot As Integer) As Boolean
    Dim As String fileName = Save_SlotFile(slot)
    If Not FileExists(fileName) Then Return True
    Return Kill(fileName) = 0
End Function
