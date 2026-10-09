'' =====================================================================
'' BeginnerChess - play.bas
'' The game screen: board, mouse control (click-click and drag-and-drop),
'' highlights, coach box, captured pieces, move list, game buttons,
'' promotion chooser, draw claims and game-over overlay.
''
'' All legality questions go to game.bas / rules.bas.
'' =====================================================================
#include once "screens.bi"

Enum MessageKind
    MSG_INFO = 0
    MSG_ERROR
    MSG_GOOD
End Enum

Type PlayState
    opts            As NewGameOptions
    humanSide       As Integer
    selected        As Integer
    deselectOnUp    As Boolean
    dragArmed       As Boolean
    dragging        As Boolean
    dragSq          As Integer
    pressX          As Integer
    pressY          As Integer
    animActive      As Boolean
    animStart       As Double
    animDur         As Double
    animFrom        As Integer
    animTo          As Integer
    animPc          As Integer
    anim2From       As Integer
    anim2To         As Integer
    anim2Pc         As Integer
    message         As String
    messageKind     As Integer
    messageTime     As Double
    errorSq         As Integer
    errorTime       As Double
    overlayClosed   As Boolean
    promoActive     As Boolean
    promoFrom       As Integer
    promoTo         As Integer
    pendingMove     As ChessMove
    pendingAnimate  As Boolean
    listScroll      As Integer
    listAutoScroll  As Boolean
    legalHash       As ULongInt
    legalPly        As Integer
    engineParams    As EngineParams
    engineMovePending As Boolean
    engineRes       As EngineResult
    thinkStart      As Double
    losingStreak    As Integer
    pendingSound    As Integer      '' played when the animation lands (-1 = none)
    lastOver        As Boolean      '' to notice when the game has just ended
    kind            As Integer      '' GameKind
    rated           As Boolean      '' career/tournament game: no take-backs
    oppName         As String
    oppRating       As Integer
    careerIndex     As Integer
    usedUndo        As Boolean      '' take-backs make a game unrated
    unrated         As Boolean      '' started from a position / loaded
    recorded        As Boolean      '' already added to the statistics
    ratingText      As String
    practice        As Boolean      '' practice mode
    showThreats     As Boolean
    hintMove        As ChessMove    '' shown as an arrow until the next move
    threatKey       As ULongInt
    threatMarks(0 To 127) As UByte
    practicePaused  As Boolean      '' after a mistake: computer waits (Undo / Play on)
    practiceWarn    As String
End Type

Dim Shared PS As PlayState
Dim Shared PlayGame As ChessGame
Dim Shared PlayBoard As BoardView
Dim Shared SmallPieces As PieceImages
Dim Shared PlayLegal As MoveList
Dim Shared PlayDlg As DialogState

Const MESSAGE_SECONDS = 9.0

'' ---------------------------------------------------------------------
'' Helpers
'' ---------------------------------------------------------------------
Private Sub SetMessage(ByRef text As Const String, ByVal kind As Integer)
    PS.message = text
    PS.messageKind = kind
    PS.messageTime = Timer
End Sub

Private Sub RefreshLegal()
    If PS.legalHash = PlayGame.pos.hash AndAlso PS.legalPly = PlayGame.pos.historyCount Then Exit Sub
    If Game_IsOver(PlayGame) Then
        PlayLegal.count = 0
    Else
        Pos_GenerateLegal(PlayGame.pos, PlayLegal)
    End If
    PS.legalHash = PlayGame.pos.hash
    PS.legalPly = PlayGame.pos.historyCount
End Sub

'' Forces a legal-move refresh (needed when the game result changes but
'' the position does not, e.g. resignation or undoing a resignation).
Private Sub InvalidateLegal()
    PS.legalPly = -1
End Sub

'' 0 = not a legal target, 1 = quiet move, 2 = capture
Private Function TargetKind(ByVal fromSq As Integer, ByVal toSq As Integer) As Integer
    Dim As Integer i
    For i = 0 To PlayLegal.count - 1
        If PlayLegal.moves(i).fromSq = fromSq AndAlso PlayLegal.moves(i).toSq = toSq Then
            Return IIf((PlayLegal.moves(i).flags And MF_CAPTURE) <> 0, 2, 1)
        End If
    Next
    Return 0
End Function

Private Function VsComputer() As Boolean
    Return PS.opts.opponent = OPP_COMPUTER
End Function

'' True when it is the computer's turn to move.
Private Function IsEngineTurn() As Boolean
    If Not VsComputer() OrElse Game_IsOver(PlayGame) Then Return False
    Return PlayGame.pos.sideToMove <> PS.humanSide
End Function

'' "White" / "Black", or "You" / "Computer" against the computer.
Private Function OppName() As String
    If PS.rated Then Return PS.oppName
    Return "Computer"
End Function

Private Function PlayerName(ByVal side As Integer) As String
    If Not VsComputer() Then Return Side_Name(side)
    Return IIf(side = PS.humanSide, "You", OppName())
End Function

Private Sub CancelEngine()
    Engine_StopAsync()
    PS.engineMovePending = False
End Sub

'' Can the user pick up the piece on sq right now?
Private Function CanSelect(ByVal sq As Integer) As Boolean
    If sq = NO_SQUARE OrElse Game_IsOver(PlayGame) Then Return False
    Dim As Integer pc = PlayGame.pos.board(sq)
    If pc = PC_EMPTY Then Return False
    If PIECE_COLOR(pc) <> PlayGame.pos.sideToMove Then Return False
    If PS.opts.opponent = OPP_COMPUTER AndAlso PIECE_COLOR(pc) <> PS.humanSide Then Return False
    Return True
End Function

'' Sound for a move that was just played (position after the move).
Private Function MoveSound(ByRef m As ChessMove) As Integer
    If Game_IsOver(PlayGame) Then Return -1           '' the end-of-game sound follows
    If Pos_InCheck(PlayGame.pos) Then Return SND_CHECK
    If m.promotion <> PT_NONE Then Return SND_PROMOTE
    If m.flags And MF_CASTLE Then Return SND_CASTLE
    If m.flags And MF_CAPTURE Then Return SND_CAPTURE
    Return SND_MOVE
End Function

Private Sub PlayEndSound()
    If Not Game_IsOver(PlayGame) Then Exit Sub
    If PlayGame.result = RESULT_DRAW Then
        Audio_Play(SND_DRAW)
    ElseIf VsComputer() Then
        Dim As Integer winner = IIf(PlayGame.result = RESULT_WHITE_WINS, SIDE_WHITE, SIDE_BLACK)
        Audio_Play(IIf(winner = PS.humanSide, SND_VICTORY, SND_DEFEAT))
    ElseIf PlayGame.termination = TERM_CHECKMATE Then
        Audio_Play(SND_CHECKMATE)
    Else
        Audio_Play(SND_VICTORY)
    End If
End Sub

'' Ends a running animation and plays the sound waiting for it.
Private Sub FinishAnimation()
    PS.animActive = False
    If PS.pendingSound >= 0 Then Audio_Play(PS.pendingSound)
    PS.pendingSound = -1
End Sub

Private Sub StartAnimation(ByRef m As ChessMove)
    PS.animActive = False
    If AppConfig.animationMs <= 0 Then Exit Sub
    PS.animActive = True
    PS.animStart = Timer
    PS.animDur = AppConfig.animationMs / 1000.0
    PS.animFrom = m.fromSq
    PS.animTo = m.toSq
    PS.animPc = PlayGame.pos.board(m.toSq)          '' (already the promoted piece)
    PS.anim2From = NO_SQUARE
    PS.anim2To = NO_SQUARE
    If m.flags And MF_CASTLE Then
        If m.toSq > m.fromSq Then
            PS.anim2From = m.toSq + 1 : PS.anim2To = m.toSq - 1
        Else
            PS.anim2From = m.toSq - 2 : PS.anim2To = m.toSq + 1
        End If
        PS.anim2Pc = PlayGame.pos.board(PS.anim2To)
    End If
End Sub

Private Sub DoMove(ByRef m As ChessMove, ByVal animate As Boolean)
    Dim As String errMsg
    If Not Game_PlayMove(PlayGame, m, errMsg) Then
        SetMessage(errMsg, MSG_ERROR)
        Exit Sub
    End If
    FinishAnimation()
    PS.hintMove.piece = PC_EMPTY
    If animate Then StartAnimation(m)
    Dim As Integer snd = MoveSound(m)
    If PS.animActive Then
        PS.pendingSound = snd
    ElseIf snd >= 0 Then
        Audio_Play(snd)
    End If
    Play_Autosave()
    PS.selected = NO_SQUARE
    PS.listAutoScroll = True
    PS.message = ""
    If Game_IsOver(PlayGame) Then
        PS.overlayClosed = False
    ElseIf Pos_InCheck(PlayGame.pos) Then
        If Not VsComputer() Then
            SetMessage(Side_Name(PlayGame.pos.sideToMove) & " is in check! The king must be protected.", MSG_ERROR)
        ElseIf PlayGame.pos.sideToMove = PS.humanSide Then
            SetMessage("You are in check! Protect your king: move it, block the check, or capture the attacker.", MSG_ERROR)
        Else
            SetMessage("Check! You are attacking the computer's king.", MSG_GOOD)
        End If
    End If
End Sub

'' Plays m, first offering a draw claim if the move allows one.
Declare Sub PracticeBeforeMove()
Declare Sub PracticeAfterMove(ByRef played As ChessMove)

Private Sub CommitMove(ByRef m As ChessMove, ByVal animate As Boolean)
    Dim As GameTermination t = Game_ClaimableDrawWithMove(PlayGame, m)
    If t <> TERM_NONE Then
        PS.pendingMove = m
        PS.pendingAnimate = animate
        Dim As String why = IIf(t = TERM_THREEFOLD, _
            "This move repeats the same position for the third time.", _
            "With this move, 50 moves in a row have been played without a capture or a pawn move.")
        Dim As String n = Notation_MoveToSAN(PlayGame.pos, m)
        Dim As String tmpTxt = why & " " & Side_Name(PlayGame.pos.sideToMove) & _
            " may claim a draw now (tournament rules), or simply play " & n & " and continue."
        Dialog_Open(PlayDlg, "claimmove", "Claim a draw?", tmpTxt, "Claim draw|Play on")
        Exit Sub
    End If
    '' Practice: compare the move with the engine's choice.
    Dim As Boolean judge = PS.practice AndAlso CBool(PlayGame.pos.sideToMove = PS.humanSide)
    If judge Then PracticeBeforeMove()
    DoMove(m, animate)
    If judge Then PracticeAfterMove(m)
End Sub

'' Practice mode: judge the player's move right after it was played.
Dim Shared PracticeBefore As Integer
Dim Shared PracticeBest As ChessMove
Dim Shared PracticeBestSan As String

Sub PracticeBeforeMove()
    If Not PS.practice Then Exit Sub
    Dim As EngineParams prm
    Engine_LevelParams(LEVEL_ADVANCED, STYLE_BALANCED, prm)
    prm.timeLimitMs = 250 : prm.maxDepth = 10 : prm.bookPlies = 0 : prm.contempt = 0
    Dim As EngineResult r
    If Engine_Search(PlayGame.pos, prm, r) Then
        PracticeBefore = r.score
        PracticeBest = r.bestMove
        PracticeBestSan = Notation_MoveToSAN(PlayGame.pos, r.bestMove)
    Else
        PracticeBefore = 0
        PracticeBest.piece = PC_EMPTY
    End If
End Sub

Sub PracticeAfterMove(ByRef played As ChessMove)
    If Not PS.practice OrElse Game_IsOver(PlayGame) Then Exit Sub
    If PracticeBest.piece = PC_EMPTY OrElse Move_Equal(played, PracticeBest) Then Exit Sub
    Dim As EngineParams prm
    Engine_LevelParams(LEVEL_ADVANCED, STYLE_BALANCED, prm)
    prm.timeLimitMs = 250 : prm.maxDepth = 10 : prm.bookPlies = 0 : prm.contempt = 0
    Dim As EngineResult r
    If Not Engine_Search(PlayGame.pos, prm, r) Then Exit Sub
    Dim As Double before = 100.0 / (1 + 10 ^ (-IIf(PracticeBefore > 2000, 2000, IIf(PracticeBefore < -2000, -2000, PracticeBefore)) / 400.0))
    Dim As Integer afterScore = -r.score
    Dim As Double after = 100.0 / (1 + 10 ^ (-IIf(afterScore > 2000, 2000, IIf(afterScore < -2000, -2000, afterScore)) / 400.0))
    If before - after >= 15 Then
        '' The computer waits so that the warning can be read.
        PS.practiceWarn = "Careful! " & Coach_ExplainThreat(PlayGame.pos, r.bestMove) & " Better was " & _
                          PracticeBestSan & ". Press Undo to try again, or Play on."
        PS.practicePaused = True
        SetMessage(PS.practiceWarn, MSG_ERROR)
    End If
End Sub

Private Sub AttemptMove(ByVal fromSq As Integer, ByVal toSq As Integer, ByVal animate As Boolean)
    Dim As Integer i, count = 0, found = -1
    For i = 0 To PlayLegal.count - 1
        If PlayLegal.moves(i).fromSq = fromSq AndAlso PlayLegal.moves(i).toSq = toSq Then
            count += 1
            found = i
        End If
    Next
    If count = 0 Then
        Dim As String why = Explain_IllegalMove(PlayGame.pos, fromSq, toSq)
        If why <> "" Then SetMessage(why, MSG_ERROR)
        Audio_Play(SND_ILLEGAL)
        PS.errorSq = toSq
        PS.errorTime = Timer
        PS.selected = NO_SQUARE
        Exit Sub
    End If
    If count > 1 Then
        '' Several moves with the same squares = a pawn promotion.
        PS.promoActive = True
        PS.promoFrom = fromSq
        PS.promoTo = toSq
        Exit Sub
    End If
    CommitMove(PlayLegal.moves(found), animate)
End Sub

Private Sub UndoMove()
    If PS.rated AndAlso Not Game_IsOver(PlayGame) Then Exit Sub     '' no take-backs in rated games
    If PlayGame.moveCount > 0 AndAlso VsComputer() Then PS.usedUndo = True
    CancelEngine()
    PS.practicePaused = False
    Dim As GameTermination t = PlayGame.termination
    If Game_Undo(PlayGame) Then
        '' Against the computer, take back its reply as well so that it is
        '' the player's turn again (but a resignation or claim is only undone).
        Select Case t
        Case TERM_RESIGNATION, TERM_AGREEMENT, TERM_THREEFOLD, TERM_FIFTY_MOVE
        Case Else
            If VsComputer() AndAlso PlayGame.pos.sideToMove <> PS.humanSide AndAlso PlayGame.moveCount > 0 Then
                Game_Undo(PlayGame)
            End If
        End Select
        PS.selected = NO_SQUARE
        PS.animActive = False
        PS.overlayClosed = False
        PS.listAutoScroll = True
        PS.losingStreak = 0
        InvalidateLegal()
        Play_Autosave()
        SetMessage("Move taken back.", MSG_INFO)
    End If
End Sub

'' ---------------------------------------------------------------------
'' Saving and sharing
'' ---------------------------------------------------------------------
Private Sub GetSetup(ByRef su As SaveSetup)
    su.opponent = PS.opts.opponent
    su.playAs = PS.opts.playAs
    su.difficulty = PS.opts.difficulty
    su.style = PS.opts.style
    su.humanSide = PS.humanSide
    su.flipped = PlayBoard.flipped
    su.practice = PS.practice
End Sub

Sub Play_Autosave()
    If PS.rated Then Exit Sub            '' rated games are not saved
    Dim As String errMsg
    If Game_IsOver(PlayGame) OrElse PlayGame.moveCount = 0 Then
        Save_Delete(0)
    Else
        Dim As SaveSetup su
        GetSetup(su)
        Save_Write(0, PlayGame, su, errMsg)
    End If
End Sub

Function Play_SaveToSlot(ByVal slot As Integer, ByRef errMsg As String) As Boolean
    Dim As SaveSetup su
    GetSetup(su)
    Return Save_Write(slot, PlayGame, su, errMsg)
End Function

Private Sub TagsForExport(ByRef tags As PgnTags)
    Dim As SaveSetup su
    GetSetup(su)
    Pgn_SetTag(tags, "Event", IIf(VsComputer(), IIf(PS.practice, "Practice game", "Game against the computer"), "Two-player game"))
    Pgn_SetTag(tags, "Site", "Beginner Chess")
    Pgn_SetTag(tags, "Date", Pgn_Today())
    Pgn_SetTag(tags, "Round", "-")
    Pgn_SetTag(tags, "White", Save_PlayerName(su, SIDE_WHITE))
    Pgn_SetTag(tags, "Black", Save_PlayerName(su, SIDE_BLACK))
    If PS.kind = GK_CAREER OrElse PS.kind = GK_TOURNAMENT Then
        '' Career and tournament games carry the real names and the event.
        Dim As String me = Profile_Current()->name
        Dim As String opp = PS.oppName & " (computer)"
        Pgn_SetTag(tags, "White", IIf(PS.humanSide = SIDE_WHITE, me, opp))
        Pgn_SetTag(tags, "Black", IIf(PS.humanSide = SIDE_WHITE, opp, me))
        If PS.kind = GK_CAREER Then
            Pgn_SetTag(tags, "Event", "Beginner Chess Career")
            Pgn_SetTag(tags, "Round", Str(PS.careerIndex + 1))
        Else
            Pgn_SetTag(tags, "Event", Tour_TierName(Tour_ActiveTier()))
            Pgn_SetTag(tags, "Round", Str(Tour_Round()))
        End If
    End If
    Dim As String eco = Book_OpeningEco(PlayGame.pos)
    If eco <> "" Then
        Pgn_SetTag(tags, "ECO", eco)
        Pgn_SetTag(tags, "Opening", Book_OpeningName(PlayGame.pos))
    End If
    If Game_IsOver(PlayGame) Then
        Dim As String term
        Select Case PlayGame.termination
        Case TERM_RESIGNATION : term = "resignation"
        Case TERM_AGREEMENT : term = "draw agreed"
        Case Else : term = "normal"
        End Select
        Pgn_SetTag(tags, "Termination", term)
    End If
End Sub

Private Sub ExportPGN()
    If Not Save_EnsureDirectory() Then
        SetMessage("The folder for saved games could not be created.", MSG_ERROR)
        Exit Sub
    End If
    Dim As PgnTags tags
    TagsForExport(tags)
    Dim As String d = Date(), t = Time()
    Dim As String stamp = Mid(d, 7, 4) & Left(d, 2) & Mid(d, 4, 2) & "_" & Left(t, 2) & Mid(t, 4, 2) & Right(t, 2)
    Dim As String fileName = Save_Directory() & "/BeginnerChess_" & stamp & ".pgn"
    If Pgn_WriteFile(fileName, Pgn_Export(PlayGame, tags)) Then
        SetMessage("Game exported as PGN: " & fileName, MSG_GOOD)
    Else
        SetMessage("Sorry, the PGN file could not be written: " & fileName, MSG_ERROR)
    End If
End Sub

Private Sub CopyFEN()
    Dim As String fen = Pos_GetFEN(PlayGame.pos)
    If Save_EnsureDirectory() Then Pgn_WriteFile(Save_Directory() & "/position.fen", fen & Chr(10))
    If Clipboard_SetText(fen) Then
        SetMessage("Position copied (FEN): " & fen, MSG_GOOD)
    Else
        Dialog_Open(PlayDlg, "fenshow", "Position (FEN)", _
                    "Copying is not available on this computer, so here is the position. It was also saved in " & _
                    Save_Directory() & "/position.fen|" & fen, "OK")
    End If
End Sub

Sub Play_ShowMessage(ByRef text As Const String)
    SetMessage(text, MSG_INFO)
End Sub

'' ---------------------------------------------------------------------
'' Start / stop
'' ---------------------------------------------------------------------
Sub Play_Start(ByRef opts As NewGameOptions)
    PS.opts = opts
    Select Case opts.playAs
    Case 0 : PS.humanSide = SIDE_WHITE
    Case 1 : PS.humanSide = SIDE_BLACK
    Case Else : PS.humanSide = IIf(Rnd < 0.5, SIDE_WHITE, SIDE_BLACK)
    End Select
    CancelEngine()
    Engine_NewGame()
    Engine_LevelParams(opts.difficulty, opts.style, PS.engineParams)
    Game_New(PlayGame)
    PlayBoard.flipped = (PS.humanSide = SIDE_BLACK)
    PS.selected = NO_SQUARE
    PS.dragArmed = False
    PS.dragging = False
    PS.deselectOnUp = False
    PS.animActive = False
    PS.promoActive = False
    PS.overlayClosed = False
    PS.errorSq = NO_SQUARE
    PS.listScroll = 0
    PS.listAutoScroll = True
    PlayDlg.active = False
    InvalidateLegal()
    PS.message = ""
    PS.losingStreak = 0
    PS.pendingSound = -1
    PS.lastOver = False
    PS.kind = IIf(opts.opponent = OPP_COMPUTER, GK_FREE, GK_TWO_PLAYER)
    PS.rated = False
    PS.oppName = "Computer (" & Engine_LevelName(opts.difficulty) & ")"
    PS.oppRating = LevelRating(opts.difficulty)
    PS.careerIndex = -1
    PS.usedUndo = False
    PS.unrated = False
    PS.recorded = False
    PS.ratingText = ""
    PS.practice = False
    PS.practicePaused = False
    PS.practiceWarn = ""
    PS.showThreats = False
    PS.hintMove.piece = PC_EMPTY
    PS.threatKey = 0
    Audio_Play(SND_START)
    If opts.playAs = 2 Then
        If opts.opponent = OPP_COMPUTER Then
            SetMessage("The coin says: you play " & Side_Name(PS.humanSide) & ".", MSG_INFO)
        Else
            SetMessage("The coin says: " & Side_Name(PS.humanSide) & " is at the bottom of the board.", MSG_INFO)
        End If
    End If
End Sub

'' Sets up the screen for a game already placed in PlayGame.
Private Sub AfterGameLoaded()
    PS.selected = NO_SQUARE
    PS.animActive = False
    PS.promoActive = False
    PS.overlayClosed = False
    PS.listAutoScroll = True
    PS.engineMovePending = False
    PS.losingStreak = 0
    PS.pendingSound = -1
    PS.lastOver = Game_IsOver(PlayGame)          '' no fanfare for a finished game being opened
    PS.unrated = True                            '' did not start from the normal position here
    PS.recorded = PS.lastOver
    PlayDlg.active = False
    InvalidateLegal()
End Sub

Function Play_LoadFromSlot(ByVal slot As Integer, ByRef errMsg As String) As Boolean
    CancelEngine()
    Static tmp As ChessGame
    Dim As SaveSetup su
    If Not Save_Read(slot, tmp, su, errMsg) Then Return False
    Dim As NewGameOptions opts
    opts.opponent = su.opponent : opts.playAs = su.playAs
    opts.difficulty = su.difficulty : opts.style = su.style
    If su.practice Then Play_StartPractice(opts) Else Play_Start(opts)
    PS.humanSide = su.humanSide
    PlayGame = tmp
    PlayBoard.flipped = su.flipped
    AfterGameLoaded()
    SetMessage("Game loaded from " & Save_SlotName(slot) & ". " & _
               IIf(Game_IsOver(PlayGame), "This game is already finished.", "Let's continue!"), MSG_GOOD)
    Return True
End Function

Function Play_StartFromFEN(ByRef opts As NewGameOptions, ByRef fen As Const String, ByRef errMsg As String) As Boolean
    Static tmp As ChessGame
    If Not Game_NewFromFEN(tmp, fen, errMsg) Then Return False
    Play_Start(opts)
    PlayGame = tmp
    AfterGameLoaded()
    SetMessage("Game started from the position you entered. " & Side_Name(PlayGame.pos.sideToMove) & " to move.", MSG_INFO)
    Return True
End Function

Function Play_StartFromPGN(ByRef opts As NewGameOptions, ByRef gameText As Const String, ByRef errMsg As String) As Boolean
    Static tmp As ChessGame
    Dim As PgnTags tags
    If Not Pgn_ParseGame(gameText, tmp, tags, errMsg) Then Return False
    Play_Start(opts)
    PlayGame = tmp
    AfterGameLoaded()
    SetMessage("Imported: " & Pgn_GetTag(tags, "White", "?") & " - " & Pgn_GetTag(tags, "Black", "?") & _
               " (" & PlayGame.moveCount & " moves). Use Undo to step back through the game.", MSG_INFO)
    Return True
End Function

Function Play_StartFromGamePrefix(ByRef opts As NewGameOptions, ByRef g As ChessGame, _
                                  ByVal plies As Integer, ByRef errMsg As String) As Boolean
    Static tmp As ChessGame
    tmp = g
    '' Take back moves (and any recorded result) until 'plies' remain.
    Dim As Integer guard = 0
    Do While (tmp.moveCount > plies OrElse Game_IsOver(tmp)) AndAlso guard < MAX_HISTORY
        If Not Game_Undo(tmp) Then Exit Do
        guard += 1
    Loop
    If Game_IsOver(tmp) Then
        errMsg = "This position is already finished."
        Return False
    End If
    Dim As NewGameOptions o = opts
    o.opponent = OPP_COMPUTER
    o.playAs = IIf(tmp.pos.sideToMove = SIDE_WHITE, 0, 1)
    Play_Start(o)
    PlayGame = tmp
    AfterGameLoaded()
    SetMessage("You take over " & Side_Name(PS.humanSide) & " in this famous game. Good luck against the computer (" & _
               Engine_LevelName(o.difficulty) & ")!", MSG_INFO)
    Return True
End Function

Sub Play_StartPractice(ByRef opts As NewGameOptions)
    Dim As NewGameOptions o = opts
    o.opponent = OPP_COMPUTER
    Play_Start(o)
    PS.practice = True
    PS.unrated = True
    SetMessage("Practice game: take back moves, ask for hints, show threats - and learn from every mistake!", MSG_INFO)
End Sub

'' Starts the same kind of game again (practice stays practice).
Private Sub RestartGame()
    If PS.practice Then Play_StartPractice(PS.opts) Else Play_Start(PS.opts)
End Sub

'' Practice: ask the engine for the best move and explain it.
Private Sub ShowHint()
    If IsEngineTurn() OrElse Game_IsOver(PlayGame) Then Exit Sub
    Dim As EngineParams prm
    Engine_LevelParams(LEVEL_ADVANCED, STYLE_BALANCED, prm)
    prm.timeLimitMs = 700 : prm.maxDepth = 12 : prm.bookPlies = 0 : prm.contempt = 0
    Dim As EngineResult r
    If Not Engine_Search(PlayGame.pos, prm, r) Then Exit Sub
    PS.hintMove = r.bestMove
    SetMessage("Hint: try " & Notation_MoveToSAN(PlayGame.pos, r.bestMove) & ". " & _
               Coach_ExplainMove(PlayGame.pos, r.bestMove), MSG_GOOD)
End Sub

Sub Play_StartRated(ByVal kind As Integer, ByRef opp As Opponent, ByVal humanSide As Integer, _
                    ByVal careerIndex As Integer)
    Dim As NewGameOptions o
    o.opponent = OPP_COMPUTER
    o.playAs = IIf(humanSide = SIDE_WHITE, 0, 1)
    o.difficulty = opp.level
    o.style = opp.style
    Play_Start(o)
    PS.kind = kind
    PS.rated = True
    PS.oppName = opp.name
    PS.oppRating = opp.rating
    PS.careerIndex = careerIndex
    SetMessage("Your opponent: " & opp.name & " (" & opp.rating & "). " & opp.bio & " No take-backs in this game!", MSG_INFO)
End Sub

'' Adds the finished game to the player's statistics, career and tournament.
'' All career and tournament games of the current player.
Function Play_TournamentPgnFile() As String
    Return Profile_Dir() & "/tournament_games.pgn"
End Function

Private Sub RecordFinishedGame()
    If PS.recorded Then Exit Sub
    PS.recorded = True
    Dim As GameRecord rec
    rec.kind = PS.kind
    rec.opponent = PS.oppName
    rec.oppRating = PS.oppRating
    rec.level = PS.opts.difficulty
    rec.plies = PlayGame.moveCount
    If PlayGame.result = RESULT_DRAW Then
        rec.score = 0.5
    Else
        Dim As Integer winner = IIf(PlayGame.result = RESULT_WHITE_WINS, SIDE_WHITE, SIDE_BLACK)
        rec.score = IIf(winner = PS.humanSide, 1, 0)
        rec.byMate = (PlayGame.termination = TERM_CHECKMATE) AndAlso (winner = PS.humanSide)
    End If
    '' Did the player castle or promote? (moves of the player's side)
    Dim As Integer i, side = PlayGame.pos.sideToMove
    For i = PlayGame.pos.historyCount - 1 To 0 Step -1
        side Xor= 1
        If side = PS.humanSide OrElse PS.kind = GK_TWO_PLAYER Then
            Dim As ChessMove mv = PlayGame.pos.undoStack(i).mv
            If (mv.flags And MF_CASTLE) <> 0 Then rec.castled = True
            If mv.promotion <> PT_NONE Then rec.promoted = True
        End If
    Next
    rec.rated = VsComputer() AndAlso (Not PS.usedUndo) AndAlso (Not PS.unrated) AndAlso CBool(PlayGame.moveCount >= 2)
    Dim As Integer change = Profile_RecordGame(rec)
    Dim As PlayerProfile Ptr pr = Profile_Current()
    If VsComputer() Then
        If rec.rated Then
            PS.ratingText = "Your rating: " & pr->rating & " (" & IIf(change >= 0, "+", "") & change & ")"
        ElseIf PS.usedUndo Then
            PS.ratingText = "This game did not change your rating, because take-backs were used."
        Else
            PS.ratingText = "This game did not change your rating."
        End If
    End If
    If PS.kind = GK_CAREER AndAlso rec.score >= 1 AndAlso PS.careerIndex = pr->careerStage Then
        pr->careerStage += 1
        Profile_Save()
        PS.ratingText &= "|You beat " & PS.oppName & " - the next opponent is unlocked!"
    End If
    '' Career and tournament games are kept in the player's PGN file.
    If PS.kind = GK_CAREER OrElse PS.kind = GK_TOURNAMENT Then
        Dim As PgnTags tags
        TagsForExport(tags)
        If Not Pgn_WriteFile(Play_TournamentPgnFile(), Pgn_Export(PlayGame, tags) & Chr(10), True) Then
            PS.ratingText &= "|(The game could not be added to your PGN file.)"
        End If
    End If
    If PS.kind = GK_TOURNAMENT Then
        Tour_RecordPlayerResult(IIf(rec.score >= 1, 2, IIf(rec.score > 0, 1, 0)))
    End If
    App_CheckAchievements()
End Sub

Sub Play_Shutdown()
    CancelEngine()
    Board_Free(PlayBoard)
    Pieces_Free(SmallPieces)
End Sub

'' ---------------------------------------------------------------------
'' Board area
'' ---------------------------------------------------------------------
Private Sub HandleBoardInput(ByVal blocked As Boolean)
    If blocked Then
        PS.dragArmed = False
        PS.dragging = False
        Exit Sub
    End If
    Dim As Integer sqUnder = Board_SquareAt(PlayBoard, UI.mx, UI.my)
    If UI.blockInput Then sqUnder = NO_SQUARE

    Dim As Boolean clickedBoard = UI.pressed AndAlso (sqUnder <> NO_SQUARE)
    If clickedBoard AndAlso IsEngineTurn() Then
        SetMessage("Please wait - " & OppName() & " is thinking about the next move.", MSG_INFO)
        Exit Sub
    End If
    If UI.pressed AndAlso sqUnder <> NO_SQUARE Then
        If PS.animActive Then FinishAnimation()   '' a click finishes any animation
        PS.deselectOnUp = False
        If PS.selected <> NO_SQUARE AndAlso sqUnder <> PS.selected AndAlso TargetKind(PS.selected, sqUnder) > 0 Then
            AttemptMove(PS.selected, sqUnder, True)
        ElseIf CanSelect(sqUnder) Then
            If PS.selected = sqUnder Then PS.deselectOnUp = True
            PS.selected = sqUnder
            PS.dragArmed = True
            PS.dragSq = sqUnder
            PS.pressX = UI.mx
            PS.pressY = UI.my
            If PS.messageKind = MSG_ERROR Then PS.message = ""
        ElseIf PS.selected <> NO_SQUARE Then
            AttemptMove(PS.selected, sqUnder, True)
        ElseIf Game_IsOver(PlayGame) Then
            SetMessage("The game is over. Start a new game or take back a move.", MSG_INFO)
        ElseIf PlayGame.pos.board(sqUnder) <> PC_EMPTY Then
            SetMessage("That is " & Side_Name(PIECE_COLOR(PlayGame.pos.board(sqUnder))) & "'s piece. It is " & _
                       Side_Name(PlayGame.pos.sideToMove) & "'s turn to move.", MSG_ERROR)
        End If
    End If

    If PS.dragArmed AndAlso UI.down AndAlso Not PS.dragging Then
        If Abs(UI.mx - PS.pressX) + Abs(UI.my - PS.pressY) > 6 Then PS.dragging = True
    End If

    If UI.released Then
        If PS.dragging Then
            If sqUnder <> NO_SQUARE AndAlso sqUnder <> PS.dragSq Then
                AttemptMove(PS.dragSq, sqUnder, False)
            End If
        ElseIf PS.deselectOnUp Then
            PS.selected = NO_SQUARE
        End If
        PS.dragging = False
        PS.dragArmed = False
        PS.deselectOnUp = False
    End If
End Sub

Private Sub DrawBoardArea()
    Dim As BoardMarks mk
    Board_ClearMarks(mk)
    Dim As ChessMove lastMv = Game_LastMove(PlayGame)
    If Not Move_IsNull(lastMv) Then
        mk.lastFrom = lastMv.fromSq
        mk.lastTo = lastMv.toSq
    End If
    If Pos_InCheck(PlayGame.pos) Then mk.checkSq = PlayGame.pos.kingSq(PlayGame.pos.sideToMove)
    mk.selectedSq = PS.selected

    Dim As Integer i
    If PS.selected <> NO_SQUARE AndAlso AppConfig.showLegalMoves Then
        For i = 0 To PlayLegal.count - 1
            If PlayLegal.moves(i).fromSq = PS.selected Then
                mk.targets(PlayLegal.moves(i).toSq) = IIf((PlayLegal.moves(i).flags And MF_CAPTURE) <> 0, 2, 1)
            End If
        Next
        Dim As Integer hov = Board_SquareAt(PlayBoard, UI.mx, UI.my)
        If hov <> NO_SQUARE AndAlso Not UI.blockInput Then
            If mk.targets(hov) <> 0 Then mk.hoverSq = hov
        End If
    End If

    '' Red flash after an illegal attempt.
    If PS.errorSq <> NO_SQUARE Then
        Dim As Double age = Timer - PS.errorTime
        If age < 0.6 Then
            mk.errorSq = PS.errorSq
            mk.errorAlpha = 150 * (1 - age / 0.6)
        Else
            PS.errorSq = NO_SQUARE
        End If
    End If

    If PS.dragging Then mk.hideSq = PS.dragSq
    Dim As Single animT = 1
    If PS.animActive Then
        UI_KeepFast()
        animT = (Timer - PS.animStart) / PS.animDur
        If animT >= 1 Then
            FinishAnimation()
        Else
            mk.hideSq = PS.animTo
            mk.hideSq2 = PS.anim2To
        End If
    End If

    '' Practice: hint arrow and threatened pieces
    If PS.hintMove.piece <> PC_EMPTY Then Board_AddArrow(mk, PS.hintMove.fromSq, PS.hintMove.toSq, MARK_BLUE)
    If PS.showThreats Then
        If PS.threatKey <> PlayGame.pos.hash Then
            PS.threatKey = PlayGame.pos.hash
            Dim As Integer th(0 To 127), s2, sd
            For s2 = 0 To 127 : PS.threatMarks(s2) = 0 : Next
            For sd = 0 To 1
                Coach_ThreatenedPieces(PlayGame.pos, sd, th())
                For s2 = 0 To 127
                    '' Red: your pieces in danger.  Green: enemy pieces you can win.
                    If th(s2) > 0 Then PS.threatMarks(s2) = IIf(sd = PS.humanSide, MARK_RED, MARK_GREEN)
                Next
            Next
        End If
        For i = 0 To 127
            If PS.threatMarks(i) <> 0 Then mk.highlight(i) = PS.threatMarks(i)
        Next
    End If
    Board_Draw(PlayBoard, PlayGame.pos, mk)

    '' Moving pieces on top.
    Dim As Integer sq = PlayBoard.sqSize
    If PS.animActive Then
        Dim As Single e = 1 - (1 - animT) * (1 - animT)          '' ease-out
        Dim As Integer x0, y0, x1, y1
        Board_SquareXY(PlayBoard, PS.animFrom, x0, y0)
        Board_SquareXY(PlayBoard, PS.animTo, x1, y1)
        Board_DrawPiece(PlayBoard, PS.animPc, x0 + (x1 - x0) * e, y0 + (y1 - y0) * e)
        If PS.anim2From <> NO_SQUARE Then
            Board_SquareXY(PlayBoard, PS.anim2From, x0, y0)
            Board_SquareXY(PlayBoard, PS.anim2To, x1, y1)
            Board_DrawPiece(PlayBoard, PS.anim2Pc, x0 + (x1 - x0) * e, y0 + (y1 - y0) * e)
        End If
    End If
    If PS.dragging Then
        Board_DrawPiece(PlayBoard, PlayGame.pos.board(PS.dragSq), UI.mx - sq \ 2, UI.my - sq \ 2)
    End If
End Sub

'' Promotion chooser. Returns True while it is open (blocks the board).
Private Function DrawPromotionChooser() As Boolean
    If Not PS.promoActive Then Return False
    Dim As Integer sq = PlayBoard.sqSize
    Dim As Integer bw = sq * 4 + 5 * 14, bh = sq + 100
    Dim As Integer cx = PlayBoard.x + sq * 4, cy = PlayBoard.y + sq * 4
    Dim As Integer x = cx - bw \ 2, y = cy - bh \ 2
    Gfx_FillRect(PlayBoard.x, PlayBoard.y, sq * 8, sq * 8, RGBA(0, 0, 0, 90))
    Gfx_Panel(x, y, bw, bh, 14, RGB(252, 248, 238), RGB(110, 84, 50))
    Text_DrawCentered(cx, y + 14, "Promote your pawn! Choose a piece:", 20, RGB(60, 40, 20))
    Dim As Integer types(0 To 3) = {PT_QUEEN, PT_ROOK, PT_BISHOP, PT_KNIGHT}
    Dim As Integer i, side = PlayGame.pos.sideToMove
    For i = 0 To 3
        Dim As Integer px = x + 14 + i * (sq + 14), py = y + 46
        Dim As Boolean hov = UI_Hover(px, py, sq, sq)
        Gfx_Panel(px, py, sq, sq, 10, IIf(hov, RGB(255, 236, 170), RGB(236, 226, 206)), RGB(150, 120, 80), False)
        Board_DrawPiece(PlayBoard, MAKE_PIECE(side, types(i)), px, py)
        Text_DrawCentered(px + sq \ 2, py + sq + 6, Notation_PieceName(types(i)), 16, RGB(80, 60, 40))
        If hov Then UI_SetTooltip("promo" & i, "Turn the pawn into a " & Notation_PieceName(types(i)) & ".")
        If hov AndAlso UI.pressed Then
            Dim As ChessMove m
            If Pos_FindLegalMove(PlayGame.pos, PS.promoFrom, PS.promoTo, types(i), m) Then
                PS.promoActive = False
                UI.pressed = False
                CommitMove(m, True)
                Return True
            End If
        End If
    Next
    If UI.keyCode = KEY_ESCAPE Then
        PS.promoActive = False
        PS.selected = NO_SQUARE
        UI.keyCode = 0
    End If
    Return True
End Function

'' Game-over card over the board. Returns True while shown.
Private Function DrawGameOverOverlay(ByRef nextScreen As Integer) As Boolean
    If Not Game_IsOver(PlayGame) OrElse PS.overlayClosed OrElse PS.animActive Then Return False
    Dim As Integer sq = PlayBoard.sqSize
    Dim As Integer w = sq * 6, h = 300
    Dim As Integer x = PlayBoard.x + sq, y = PlayBoard.y + sq * 4 - h \ 2
    Dim As String title
    Select Case PlayGame.termination
    Case TERM_CHECKMATE   : title = "Checkmate!"
    Case TERM_STALEMATE   : title = "Stalemate!"
    Case TERM_RESIGNATION : title = "Game over"
    Case Else             : title = "Draw!"
    End Select
    Dim As String text = Game_StatusText(PlayGame)
    If VsComputer() AndAlso PlayGame.result <> RESULT_DRAW Then
        Dim As Integer winner = IIf(PlayGame.result = RESULT_WHITE_WINS, SIDE_WHITE, SIDE_BLACK)
        If winner = PS.humanSide Then
            If PlayGame.termination = TERM_CHECKMATE OrElse PlayGame.termination = TERM_RESIGNATION Then title = "You win!"
            If PlayGame.termination = TERM_RESIGNATION Then text = OppName() & " resigned - there was no way to stop you."
            text &= " Congratulations - you beat " & PS.oppName & "!"
        Else
            text &= " Don't give up - try again, or choose an easier level."
        End If
    ElseIf PlayGame.result <> RESULT_DRAW Then
        text &= " Well played!"
    End If

    If PS.ratingText <> "" Then
        text &= "|" & PS.ratingText
        h += 40
        y -= 20
    End If
    Gfx_FillRect(PlayBoard.x, PlayBoard.y, sq * 8, sq * 8, RGBA(0, 0, 0, 70))
    Gfx_Panel(x, y, w, h, 18, RGB(252, 248, 238), RGB(170, 120, 40))
    Text_DrawShadow(x + (w - Text_Width(title, 44)) \ 2, y + 18, title, 44, RGB(150, 90, 20), RGBA(0, 0, 0, 50))
    Dim As Integer ots = Text_FitSize(text, w - 48, h - 210, 20, 14)
    Text_DrawWrapped(x + 24, y + 80, w - 48, text, ots, RGB(50, 40, 30), True)
    If UI_Button("over.review", x + 20, y + h - 120, w - 40, 42, "Review this game", PlayGame.moveCount >= 2, _
                 "The computer looks at every move and shows the good ones and the mistakes.") Then
        Review_Start(PlayGame, SCREEN_PLAY, PlayBoard.flipped)
        PS.overlayClosed = True
        nextScreen = SCREEN_REVIEW
    End If
    Dim As Integer bw = (w - 3 * 20) \ 2
    If PS.rated Then
        If UI_Button("over.cont", x + 20, y + h - 68, bw, 50, "Continue", True, "Back to the tournament hall.", BTN_PRIMARY) Then
            nextScreen = SCREEN_TOURNAMENT
        End If
    ElseIf UI_Button("over.new", x + 20, y + h - 68, bw, 50, "New Game", True, "Play again with the same settings.", BTN_PRIMARY) Then
        RestartGame()
    End If
    If UI_Button("over.close", x + 40 + bw, y + h - 68, bw, 50, "Look at board", True, _
                 "Close this message to study the final position.") Then
        PS.overlayClosed = True
    End If
    Return True
End Function

'' ---------------------------------------------------------------------
'' Side panel
'' ---------------------------------------------------------------------
Private Function CoachText(ByRef kind As Integer) As String
    kind = MSG_INFO
    If PS.practicePaused Then
        kind = MSG_ERROR
        Return PS.practiceWarn
    End If
    If PS.message <> "" AndAlso Timer - PS.messageTime < MESSAGE_SECONDS Then
        kind = PS.messageKind
        Return PS.message
    End If
    PS.message = ""
    If Game_IsOver(PlayGame) Then
        kind = MSG_GOOD
        Return "Use 'Undo' to go back and try something different, or start a new game."
    End If
    Dim As String claim = Game_ClaimHint(PlayGame)
    If claim <> "" Then Return claim & " Press 'Claim Draw' if you want to."
    If Not AppConfig.beginnerHints Then Return ""
    If PS.selected <> NO_SQUARE Then
        Dim As Integer pt = PIECE_TYPE(PlayGame.pos.board(PS.selected))
        Dim As String nm = Notation_PieceName(pt)
        Return UCase(Left(nm, 1)) & Mid(nm, 2) & ": " & Explain_HowPieceMoves(pt)
    End If
    If Pos_InCheck(PlayGame.pos) Then
        Return "Your king is in check! Move the king, put a piece in the way, or capture the attacker."
    End If
    If PlayGame.moveCount = 0 Then
        Return "White always moves first. Click a piece (or drag it) to see where it can go."
    End If
    Select Case PlayGame.moveCount Mod 6
    Case 0 : Return "Tip: Look at your opponent's last move. What is it attacking?"
    Case 1 : Return "Tip: Try to control the centre squares d4, e4, d5 and e5."
    Case 2 : Return "Tip: Bring out your knights and bishops early, and castle to keep your king safe."
    Case 3 : Return "Tip: Before you move, check that your pieces are protected."
    Case 4 : Return "Tip: Don't bring your queen out too early - it can be chased around."
    Case Else : Return "Tip: Every move, look for checks, captures and threats."
    End Select
End Function

Private Sub DrawCaptured(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer)
    '' Count missing pieces compared with the standard starting set.
    Dim As Integer startCount(0 To 6) = {0, 8, 2, 2, 2, 1, 1}
    Dim As Integer values(0 To 6) = {0, 1, 3, 3, 5, 9, 0}
    Dim As Integer have(0 To 1, 0 To 6)
    Dim As Integer s, side, pt, material(0 To 1)
    For s = 0 To 127
        If SQ_OFFBOARD(s) Then Continue For
        Dim As Integer pc = PlayGame.pos.board(s)
        If pc <> PC_EMPTY Then
            have(PIECE_COLOR(pc), PIECE_TYPE(pc)) += 1
            material(PIECE_COLOR(pc)) += values(PIECE_TYPE(pc))
        End If
    Next
    If SmallPieces.size <> 26 OrElse SmallPieces.style <> AppConfig.pieceSet Then Pieces_Build(SmallPieces, 26, AppConfig.pieceSet)
    Gfx_Panel(x, y, w, 70, 10, RGB(246, 242, 232), RGB(150, 130, 100), False)
    For side = SIDE_WHITE To SIDE_BLACK
        Dim As Integer rowY = y + 6 + side * 30, cx = x + 10
        Dim As Integer victim = side Xor 1          '' pieces this side has captured
        Text_Draw(cx, rowY + 5, IIf(side = SIDE_WHITE, "White:", "Black:"), 16, RGB(80, 70, 60))
        cx += 60
        For pt = PT_QUEEN To PT_PAWN Step -1
            Dim As Integer missing = startCount(pt) - have(victim, pt), k
            For k = 1 To missing
                If cx > x + w - 60 Then Exit For
                Pieces_Draw(SmallPieces, MAKE_PIECE(victim, pt), cx, rowY)
                cx += IIf(pt = PT_PAWN, 13, 19)
            Next
        Next
        Dim As Integer diff = material(side) - material(victim)
        If diff > 0 Then Text_Draw(x + w - 44, rowY + 4, "+" & diff, 18, RGB(30, 120, 40))
    Next
End Sub

Private Sub DrawMoveList(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer)
    Gfx_Panel(x, y, w, h, 10, RGB(255, 255, 255), RGB(150, 130, 100), False)
    Dim As String opening = Book_OpeningName(PlayGame.pos)
    If opening = "" Then
        Text_Draw(x + 12, y + 8, "Moves", 18, RGB(110, 80, 50))
    Else
        Dim As Integer ots = 18
        Do While ots > 13 AndAlso Text_Width(opening, ots) > w - 24
            ots -= 1
        Loop
        If Text_Width(opening, ots) > w - 24 Then opening = Left(opening, (w - 30) \ (ots \ 2)) & "."
        Text_Draw(x + 12, y + 9, opening, ots, RGB(52, 100, 170))
        If UI_Hover(x, y, w, 30) Then UI_SetTooltip("opening", "The opening played in this game: " & _
            Book_OpeningEco(PlayGame.pos) & " " & Book_OpeningName(PlayGame.pos))
    End If
    Dim As Integer rowH = 24, top = y + 32
    Dim As Integer visible = (h - 40) \ rowH
    If visible < 1 Then visible = 1

    '' Work out the number/side of the first recorded move.
    Dim As Integer firstSide = PlayGame.pos.sideToMove, firstNo = PlayGame.pos.fullmoveNumber, i
    For i = 1 To PlayGame.moveCount
        firstSide Xor= 1
        If firstSide = SIDE_BLACK Then firstNo -= 1
    Next
    Dim As Integer offset = IIf(firstSide = SIDE_BLACK, 1, 0)
    Dim As Integer rows = (PlayGame.moveCount + offset + 1) \ 2

    If UI_Hover(x, y, w, h) AndAlso UI.wheelDelta <> 0 Then
        PS.listScroll -= UI.wheelDelta
        PS.listAutoScroll = False
    End If
    If PS.listAutoScroll Then PS.listScroll = rows - visible
    If PS.listScroll > rows - visible Then PS.listScroll = rows - visible
    If PS.listScroll < 0 Then PS.listScroll = 0
    If PS.listScroll >= rows - visible Then PS.listAutoScroll = True

    If PlayGame.moveCount = 0 Then
        Text_Draw(x + 12, top + 4, "No moves yet.", 18, RGB(150, 150, 150))
    End If
    Dim As Integer r
    For r = PS.listScroll To PS.listScroll + visible - 1
        If r >= rows Then Exit For
        Dim As Integer ry = top + (r - PS.listScroll) * rowH
        If (r And 1) = 1 Then Gfx_FillRect(x + 4, ry, w - 8, rowH, RGB(246, 242, 234))
        Text_Draw(x + 12, ry + 3, (firstNo + r) & ".", 18, RGB(140, 120, 100))
        Dim As Integer c
        For c = 0 To 1
            Dim As Integer ply = r * 2 + c - offset
            If ply < 0 OrElse ply >= PlayGame.moveCount Then Continue For
            Dim As Integer cx = x + 70 + c * ((w - 80) \ 2)
            If ply = PlayGame.moveCount - 1 Then
                Gfx_RoundRect(cx - 4, ry + 1, (w - 80) \ 2 - 6, rowH - 2, 5, RGB(255, 226, 120))
            End If
            Text_Draw(cx, ry + 3, PlayGame.sanMoves(ply), 18, RGB(30, 30, 40))
        Next
    Next
    If rows > visible Then
        '' Simple scroll indicator
        Dim As Integer barH = (h - 40) * visible \ rows
        Dim As Integer barY = top + (h - 40 - barH) * PS.listScroll \ IIf(rows - visible > 0, rows - visible, 1)
        Gfx_RoundRect(x + w - 9, barY, 5, barH, 2, RGB(180, 170, 160))
    End If
End Sub

'' The computer answers a draw offer from the player.
Private Sub AnswerDrawOffer()
    Dim As EngineParams prm = PS.engineParams
    prm.maxDepth = 6 : prm.timeLimitMs = 400 : prm.temperature = 0 : prm.noise = 0
    Dim As EngineResult res
    If Not Engine_Search(PlayGame.pos, prm, res) Then Exit Sub
    '' res.score is from the player's side (to move); flip it for the engine.
    Dim As Integer engineScore = -res.score
    Dim As Boolean accept
    Select Case PS.opts.style
    Case STYLE_AGGRESSIVE : accept = (engineScore <= -300)
    Case STYLE_DEFENSIVE  : accept = (engineScore <= 30)
    Case Else             : accept = (engineScore <= -150) OrElse (Abs(engineScore) <= 25 AndAlso PlayGame.moveCount >= 30)
    End Select
    If accept Then
        Game_AgreeDraw(PlayGame)
        Play_Autosave()
        PS.overlayClosed = False
        InvalidateLegal()
        SetMessage(OppName() & " accepts your draw offer.", MSG_GOOD)
    Else
        SetMessage(OppName() & " declines the draw offer and wants to play on!", MSG_INFO)
    End If
End Sub

'' Plays the move the engine has chosen (or claims a draw with it).
Private Sub ApplyEngineMove()
    PS.engineMovePending = False
    Dim As ChessMove m = PS.engineRes.bestMove
    Dim As String errMsg
    Dim As Boolean notBetter = PS.engineRes.score <= 0
    If (Not PS.engineRes.fromBook) AndAlso Engine_ShouldResign(PlayGame.pos, PS.engineRes.score, PS.losingStreak) Then
        Game_Resign(PlayGame, PlayGame.pos.sideToMove)
        PS.overlayClosed = False
        InvalidateLegal()
        Play_Autosave()
        SetMessage(OppName() & " resigns: there is no way to stop you from winning. Well played!", MSG_GOOD)
    ElseIf notBetter AndAlso Game_ClaimableDraw(PlayGame) <> TERM_NONE Then
        Game_ClaimDraw(PlayGame)
        PS.overlayClosed = False
        InvalidateLegal()
        Play_Autosave()
        SetMessage(OppName() & " claims a draw.", MSG_INFO)
    ElseIf notBetter AndAlso Game_ClaimableDrawWithMove(PlayGame, m) <> TERM_NONE Then
        If Game_ClaimDrawWithMove(PlayGame, m, errMsg) Then
            StartAnimation(m)
            PS.overlayClosed = False
            InvalidateLegal()
            SetMessage(OppName() & " plays " & PlayGame.sanMoves(PlayGame.moveCount - 1) & " and claims a draw.", MSG_INFO)
        End If
    Else
        DoMove(m, True)
    End If
End Sub

'' Starts the computer's thinking and plays its move when ready.
Private Sub UpdateEngine()
    If PS.practicePaused Then
        If Engine_IsThinking() OrElse PS.engineMovePending Then CancelEngine()
        Exit Sub
    End If
    If Not IsEngineTurn() Then
        If Engine_IsThinking() OrElse PS.engineMovePending Then CancelEngine()
        Exit Sub
    End If
    If Not PS.engineMovePending Then
        If Not Engine_IsThinking() Then
            Engine_StartAsync(PlayGame.pos, PS.engineParams)
            PS.thinkStart = Timer
        End If
        If Engine_PollAsync(PS.engineRes) Then PS.engineMovePending = True
    End If
    '' Wait for dialogs/animations, and think at least a moment (feels natural).
    If PS.engineMovePending AndAlso Not PlayDlg.active AndAlso Not PS.promoActive AndAlso Not PS.animActive Then
        If (Timer - PS.thinkStart) * 1000 >= PS.engineParams.minThinkMs OrElse UI.fakeInput Then ApplyEngineMove()
    End If
End Sub

Private Sub DrawSidePanel(ByVal x As Integer, ByVal w As Integer, ByRef nextScreen As Integer)
    Dim As Integer sh = Gfx_Height()
    Dim As Integer y = 62

    '' --- Turn / status card ---
    Dim As Integer cardH = 108
    Gfx_Panel(x, y, w, cardH, 12, RGB(252, 249, 240), RGB(150, 120, 80))
    Dim As Integer stm = PlayGame.pos.sideToMove
    Dim As Boolean over = Game_IsOver(PlayGame)
    If Not over Then
        Gfx_FillCircle(x + 34, y + 34, 18, RGB(60, 60, 60))
        Gfx_FillCircle(x + 34, y + 34, 16, IIf(stm = SIDE_WHITE, RGB(250, 250, 245), RGB(30, 30, 34)))
        If IsEngineTurn() Then
            Dim As Integer dots = Int(Timer * 3) Mod 4
            Text_Draw(x + 64, y + 14, Left(OppName(), 16), 26, RGB(40, 34, 28))
            Text_Draw(x + 64, y + 44, IIf(PS.practicePaused, "is waiting for you", "is thinking" & String(dots, ".")), 22, RGB(52, 100, 170))
        ElseIf VsComputer() Then
            Text_Draw(x + 64, y + 20, "Your move", 28, RGB(40, 34, 28))
        Else
            Text_Draw(x + 64, y + 20, Side_Name(stm) & " to move", 28, RGB(40, 34, 28))
        End If
        If Pos_InCheck(PlayGame.pos) Then
            Text_Draw(x + 64, y + 70, IIf(Pos_CountCheckers(PlayGame.pos) >= 2, "Double check!", "Check!"), 26, RGB(200, 30, 30))
        ElseIf VsComputer() Then
            If PS.rated Then
                Text_Draw(x + 64, y + 76, PS.oppName & " (" & PS.oppRating & "), " & Engine_StyleName(PS.opts.style), _
                          18, RGB(120, 110, 100))
            Else
                Text_Draw(x + 64, y + 76, Engine_LevelName(PS.opts.difficulty) & ", " & _
                          Engine_StyleName(PS.opts.style), 18, RGB(120, 110, 100))
            End If
        Else
            Text_Draw(x + 64, y + 64, "Two players", 18, RGB(120, 110, 100))
        End If
    Else
        Dim As ULong rc = IIf(PlayGame.result = RESULT_DRAW, RGB(60, 90, 160), RGB(30, 130, 50))
        Text_Draw(x + 16, y + 12, "Game over  " & Game_ResultString(PlayGame), 26, rc)
        Text_DrawWrapped(x + 16, y + 46, w - 32, Game_StatusText(PlayGame), 18, RGB(50, 44, 36))
    End If
    y += cardH + 10

    '' --- Coach box ---
    Dim As Integer coachH = 138, kind
    Dim As String coach = CoachText(kind)
    Dim As ULong fill = RGB(255, 250, 220), border = RGB(200, 170, 80), txtC = RGB(70, 56, 20)
    Dim As String heading = "Coach"
    If kind = MSG_ERROR Then
        fill = RGB(255, 236, 228) : border = RGB(210, 110, 80) : txtC = RGB(140, 40, 20) : heading = "Oops!"
    ElseIf kind = MSG_GOOD Then
        fill = RGB(232, 248, 232) : border = RGB(100, 170, 100) : txtC = RGB(30, 90, 30)
    End If
    Gfx_Panel(x, y, w, coachH, 12, fill, border, False)
    Text_Draw(x + 12, y + 8, heading, 18, Color_Shade(border, 0.7))
    If coach <> "" Then
        Dim As Integer ts = Text_FitSize(coach, w - 24, coachH - 38, 20, 15)
        Text_DrawWrapped(x + 12, y + 32, w - 24, coach, ts, txtC)
    End If
    y += coachH + 10

    '' --- Captured pieces ---
    DrawCaptured(x, y, w)
    y += 80

    '' --- Buttons (from the bottom up) ---
    Dim As Integer bh = 42, gap = 8, bw = (w - gap) \ 2
    Dim As Integer by4 = sh - 16 - bh
    Dim As Integer by3 = by4 - bh - gap, by2 = by3 - bh - gap, by1 = by2 - bh - gap

    '' --- Move list fills the remaining space ---
    DrawMoveList(x, y, w, by1 - 10 - y)

    Dim As Boolean humanTurn = Not IsEngineTurn()
    Dim As Boolean ratedLive = PS.rated AndAlso Not over
    Dim As Boolean canUndo = (CBool(PlayGame.moveCount > 0) OrElse over) AndAlso Not ratedLive
    If UI_Button("play.undo", x, by1, bw, bh, "Undo", canUndo, _
                 IIf(ratedLive, "No take-backs in career and tournament games!", _
                     "Take back the last move. (Keyboard: U)")) Then UndoMove()
    If UI_Button("play.flip", x + bw + gap, by1, bw, bh, "Flip Board", True, _
                 "Turn the board around. (Keyboard: F)") Then PlayBoard.flipped = Not PlayBoard.flipped

    If PS.practice Then
        If PS.practicePaused Then
            If UI_Button("pr.playon", x, by2, bw, bh, "Play on", True, _
                         "Keep your move and let the computer answer.", BTN_PRIMARY) Then PS.practicePaused = False
        ElseIf UI_Button("pr.hint", x, by2, bw, bh, "Hint", humanTurn AndAlso Not over, _
                         "Show the move the computer would play here, and why.", BTN_PRIMARY) Then
            ShowHint()
        End If
        If UI_Button("pr.threats", x + bw + gap, by2, bw, bh, "Threats", True, _
                     "Mark your pieces in danger (red) and enemy pieces you can win (green).", _
                     IIf(PS.showThreats, BTN_PRIMARY, BTN_NORMAL)) Then
            PS.showThreats = Not PS.showThreats
            PS.threatKey = 0
        End If
        If UI_Button("pr.switch", x, by3, bw, bh, "Switch sides", Not over, "Play the other colour from here.") Then
            CancelEngine()
            PS.practicePaused = False
            PS.humanSide Xor= 1
            PlayBoard.flipped = (PS.humanSide = SIDE_BLACK)
            PS.hintMove.piece = PC_EMPTY
            PS.threatKey = 0
            SetMessage("You now play " & Side_Name(PS.humanSide) & ".", MSG_INFO)
        End If
        If UI_Button("pr.analyze", x + bw + gap, by3, bw, bh, "Analyze", True, "Study this position with the computer.") Then
            CancelEngine()
            Analyze_Start(Pos_GetFEN(PlayGame.pos), SCREEN_PLAY)
            nextScreen = SCREEN_ANALYZE
        End If
        If UI_Button("pr.restart", x, by4, bw, bh, "Restart", True, "Start the practice game again.") Then
            RestartGame()
        End If
        If UI_Button("pr.menu", x + bw + gap, by4, bw, bh, "Main Menu", True, "Leave practice (Esc).") Then
            CancelEngine()
            nextScreen = SCREEN_MENU
        End If
        Exit Sub
    End If
    Dim As Boolean canClaim = (Game_ClaimableDraw(PlayGame) <> TERM_NONE) AndAlso humanTurn
    If UI_Button("play.claim", x, by2, bw, bh, "Claim Draw", canClaim, _
                 "Tournament rule: you may claim a draw when the same position appears for the third time, " & _
                 "or after 50 moves by each side without a capture or a pawn move.") Then
        If Game_ClaimDraw(PlayGame) Then
            PS.overlayClosed = False
            InvalidateLegal()
            Play_Autosave()
        End If
    End If
    If UI_Button("play.offer", x + bw + gap, by2, bw, bh, "Offer Draw", (Not over) AndAlso humanTurn, _
                 "Ask your opponent whether they agree to a draw.") Then
        If VsComputer() Then
            AnswerDrawOffer()
        Else
            Dialog_Open(PlayDlg, "offer", "Draw offer", _
                        Side_Name(stm) & " offers a draw. " & Side_Name(stm Xor 1) & ", do you accept?", _
                        "Accept|Decline")
        End If
    End If
    If UI_Button("play.resign", x, by3, bw, bh, "Resign", Not over, _
                 "Give up this game.", BTN_DANGER) Then
        If VsComputer() Then
            Dialog_Open(PlayDlg, "resign", "Resign?", "Do you really want to give up this game?", "Resign|Keep playing")
        Else
            Dialog_Open(PlayDlg, "resign", "Resign?", _
                        "Does " & Side_Name(stm) & " really want to give up this game?", "Resign|Keep playing")
        End If
    End If
    If UI_Button("play.new", x + bw + gap, by3, bw, bh, "New Game", Not PS.rated, _
                 IIf(PS.rated, "Career and tournament games are started from the Tournament hall.", _
                     "Start again with the same settings.")) Then
        If over OrElse PlayGame.moveCount = 0 Then
            Play_Start(PS.opts)
        Else
            Dialog_Open(PlayDlg, "newgame", "New game?", _
                        "Start a new game? The current game will be lost.", "New game|Cancel")
        End If
    End If
    If UI_Button("play.file", x, by4, bw, bh, "Save / Share", Not ratedLive, _
                 IIf(ratedLive, "Rated games cannot be saved, but you can export them when they are finished.", _
                     "Save this game, export it as a PGN file, or copy the position (FEN).")) Then
        Dialog_Open(PlayDlg, "file", "Save / Share", "What would you like to do with this game?", _
                    "Save game|Export PGN|Copy FEN|Cancel")
    End If
    If UI_Button("play.menu", x + bw + gap, by4, bw, bh, IIf(PS.rated, "Leave", "Main Menu"), True, _
                 "Leave this game. (Keyboard: Esc)") Then
        If ratedLive Then
            Dialog_Open(PlayDlg, "leave", "Leave the game?", _
                        "Leave this game? It will not count - you can play it again later from the Tournament hall.", _
                        "Leave|Stay")
        ElseIf over AndAlso PS.rated Then
            CancelEngine()
            nextScreen = SCREEN_TOURNAMENT
        ElseIf over OrElse PlayGame.moveCount = 0 Then
            CancelEngine()
            nextScreen = SCREEN_MENU
        Else
            Dialog_Open(PlayDlg, "leave", "Leave the game?", _
                        "Go back to the main menu? Your game is saved automatically - choose 'Continue Game' " & _
                        "in the main menu to come back to it.", "Leave|Stay")
        End If
    End If
End Sub

Private Sub HandleDialogResult(ByVal r As Integer, ByRef nextScreen As Integer)
    If r < 0 Then Exit Sub
    Select Case PlayDlg.id
    Case "claimmove"
        If r = 0 Then
            Dim As String errMsg
            If Game_ClaimDrawWithMove(PlayGame, PS.pendingMove, errMsg) Then
                Play_Autosave()
                PS.overlayClosed = False
                PS.selected = NO_SQUARE
                InvalidateLegal()
            End If
        Else
            DoMove(PS.pendingMove, PS.pendingAnimate)
        End If
    Case "offer"
        If r = 0 Then
            Game_AgreeDraw(PlayGame)
            Play_Autosave()
            PS.overlayClosed = False
            InvalidateLegal()
        Else
            SetMessage("The draw offer was declined. Play on!", MSG_INFO)
        End If
    Case "resign"
        If r = 0 Then
            CancelEngine()
            Game_Resign(PlayGame, IIf(VsComputer(), PS.humanSide, PlayGame.pos.sideToMove))
            Play_Autosave()
            PS.overlayClosed = False
            PS.selected = NO_SQUARE
            InvalidateLegal()
        End If
    Case "file"
        Select Case r
        Case 0
            CancelEngine()
            SaveLoad_Begin(SLMODE_SAVE, SCREEN_PLAY)
            nextScreen = SCREEN_SAVELOAD
        Case 1 : ExportPGN()
        Case 2 : CopyFEN()
        End Select
    Case "newgame"
        If r = 0 Then RestartGame()
    Case "leave"
        If r = 0 Then
            CancelEngine()
            nextScreen = IIf(PS.rated, SCREEN_TOURNAMENT, SCREEN_MENU)
        End If
    End Select
End Sub

'' ---------------------------------------------------------------------
'' Frame
'' ---------------------------------------------------------------------
Function Play_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_PLAY
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    UpdateEngine()
    RefreshLegal()

    UI.blockInput = PlayDlg.active
    UI_DrawBackground()
    If PS.kind = GK_CAREER Then
        Screen_DrawHeader("Career: You vs " & PS.oppName & " (" & PS.oppRating & ")")
    ElseIf PS.kind = GK_TOURNAMENT Then
        Screen_DrawHeader(Tour_TierName(Tour_ActiveTier()) & ", round " & Tour_Round() & ": vs " & PS.oppName)
    ElseIf PS.practice Then
        Screen_DrawHeader("Practice")
    ElseIf VsComputer() Then
        Screen_DrawHeader("You vs Computer")
    Else
        Screen_DrawHeader("Two-player game")
    End If

    '' Layout: board on the left, panel on the right.
    PlayBoard.theme = AppConfig.boardTheme
    PlayBoard.pieceSet = AppConfig.pieceSet
    PlayBoard.showCoords = AppConfig.showCoordinates
    Dim As Integer panelW = 300
    Dim As Integer avail = sh - 50 - 24
    Board_Layout(PlayBoard, 0, 0, 10)                    '' to learn the margin ratio
    Dim As Integer sq = (avail - 2 * PlayBoard.margin) \ 8
    If sq * 8 + 2 * PlayBoard.margin > sw - panelW - 48 Then sq = (sw - panelW - 48 - 2 * PlayBoard.margin) \ 8
    Board_Layout(PlayBoard, 0, 0, sq)
    Dim As Integer outer = Board_OuterSize(PlayBoard)
    Dim As Integer bx = 16 + (sw - panelW - 40 - outer) \ 2
    Board_Layout(PlayBoard, bx, 50 + (sh - 50 - outer) \ 2, sq)

    DrawBoardArea()
    '' The game has just ended (by a move, resignation, claim or agreement).
    If Not PS.animActive Then
        Dim As Boolean overNow = Game_IsOver(PlayGame)
        If overNow AndAlso Not PS.lastOver Then
            PlayEndSound()
            RecordFinishedGame()
        End If
        PS.lastOver = overNow
    End If
    Dim As Integer panelX = bx + outer + 24
    DrawSidePanel(panelX, sw - panelX - 16, nextScreen)

    '' Overlays (only one of these is active at a time).
    Dim As Boolean boardBlocked = PlayDlg.active
    If DrawPromotionChooser() Then boardBlocked = True
    If Not PlayDlg.active AndAlso DrawGameOverOverlay(nextScreen) Then boardBlocked = True
    HandleBoardInput(boardBlocked)

    If PlayDlg.active Then
        HandleDialogResult(Dialog_Run(PlayDlg), nextScreen)
    Else
        '' Keyboard shortcuts
        Select Case UI.keyCode
        Case KEY_ESCAPE
            If PS.selected <> NO_SQUARE Then
                PS.selected = NO_SQUARE
            ElseIf PS.rated AndAlso Not Game_IsOver(PlayGame) Then
                Dialog_Open(PlayDlg, "leave", "Leave the game?", _
                            "Leave this game? It will not count - you can play it again later from the Tournament hall.", _
                            "Leave|Stay")
            ElseIf Game_IsOver(PlayGame) OrElse PlayGame.moveCount = 0 Then
                CancelEngine()
                nextScreen = IIf(PS.rated, SCREEN_TOURNAMENT, SCREEN_MENU)
            Else
                Dialog_Open(PlayDlg, "leave", "Leave the game?", _
                            "Go back to the main menu? Your game is saved automatically - choose 'Continue Game' " & _
                            "in the main menu to come back to it.", "Leave|Stay")
            End If
        Case Asc("f"), Asc("F")
            PlayBoard.flipped = Not PlayBoard.flipped
        Case Asc("u"), Asc("U"), KEY_BACKSPACE, KEY_LEFT
            UndoMove()
        End Select
    End If
    Return nextScreen
End Function

'' ---------------------------------------------------------------------
'' Debug / screenshot hooks
'' ---------------------------------------------------------------------
Function Play_DebugMoves(ByRef moves As Const String) As Boolean
    Dim As String rest = Trim(moves) & " ", errMsg
    Do While Len(Trim(rest)) > 0
        Dim As Integer sp = InStr(rest, " ")
        Dim As String mv = Left(rest, sp - 1)
        rest = LTrim(Mid(rest, sp + 1))
        If Not Game_PlayMoveText(PlayGame, mv, errMsg) Then Return False
    Loop
    PS.listAutoScroll = True
    If Game_IsOver(PlayGame) Then PS.overlayClosed = False
    InvalidateLegal()
    Return True
End Function

Sub Play_DebugSelect(ByRef sqName As Const String)
    PS.selected = Sq_Parse(sqName)
End Sub

Sub Play_DebugPromotion(ByRef fromName As Const String, ByRef toName As Const String)
    PS.promoActive = True
    PS.promoFrom = Sq_Parse(fromName)
    PS.promoTo = Sq_Parse(toName)
End Sub

Sub Play_DebugClick(ByRef sqName As Const String)
    RefreshLegal()
    Dim As Integer sq = Sq_Parse(sqName)
    If PS.selected <> NO_SQUARE AndAlso sq <> PS.selected Then
        AttemptMove(PS.selected, sq, False)
    Else
        PS.selected = sq
    End If
End Sub

Function Play_DebugFEN(ByRef fen As Const String) As Boolean
    Dim As String errMsg
    If Not Game_NewFromFEN(PlayGame, fen, errMsg) Then Return False
    InvalidateLegal()
    Return True
End Function

Function Play_DebugMoveCount() As Integer
    Return PlayGame.moveCount
End Function

Sub Play_DebugOpenFileMenu()
    Dialog_Open(PlayDlg, "file", "Save / Share", "What would you like to do with this game?", _
                "Save game|Export PGN|Copy FEN|Cancel")
End Sub

Sub Play_DebugPractice()
    PS.showThreats = True
    PS.threatKey = 0
    ShowHint()
End Sub
