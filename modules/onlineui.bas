'' =====================================================================
'' BeginnerChess - onlineui.bas
'' Play Online: the online home screen (connection, guest name, quick
'' match, players online) and the online game screen.
''
'' OnlineUI_Pump runs every frame on every screen (from the main loop): it
'' keeps the connection alive and reacts to server events, so nothing is
'' lost while another screen (e.g. the game review) is open.
'' The online game screen shows what the server confirms. Fair play: there
'' are no hints, take-backs, threat markers or engine analysis here.
'' =====================================================================
#include once "screens.bi"
#include once "online.bi"
#include once "boardctl.bi"
#include once "tokenstore.bi"

Const OUI_MSG_INFO = 0, OUI_MSG_GOOD = 1, OUI_MSG_BAD = 2
Const MINUTE_OPTIONS = "3 minutes|5 minutes|10 minutes|15 minutes|30 minutes"
Const INCREMENT_OPTIONS = "no increment|+2 seconds|+5 seconds|+10 seconds"

Type OnlineUIState
    nameDlg        As InputDialogState
    serverDlg      As InputDialogState
    dlg            As DialogState
    message        As String
    messageKind    As Integer
    messageTime    As Double
    wantLogin      As Boolean        '' log in as guest as soon as the server greets us
    subscribed     As Boolean        '' receiving lobby updates
    lobbyScroll    As Integer
    '' Game screen
    gameId         As String
    pos            As Position       '' position shown (server position + our pending move)
    shownPly       As Integer        '' server ply the board is based on
    pendingMove    As String         '' our move sent, not yet confirmed
    flipped        As Boolean
    overlayClosed  As Boolean
    endHandled     As Boolean
    listScroll     As Integer
    '' Accounts
    credDlg        As InputDialogState   '' user name / password steps
    flowUser       As String
    flowPass       As String              '' only between two dialog steps, then cleared
    remember       As Boolean             '' keep the session token ("remember me")
    profileName    As String              '' "" = own profile
    histOffset     As Integer
    '' Phase 7
    rated          As Integer             '' 0 casual, 1 rated (quick match and challenges)
    chDlg          As DialogState         '' an incoming challenge
    chDlgId        As String              '' its challenge id
    leaderOffset   As Integer
End Type

Dim Shared OUI As OnlineUIState
Dim Shared OnlineBoard As BoardView
Dim Shared OnlineBC As BoardControl
Dim Shared ReviewGame As ChessGame           '' the finished online game, for the review screen

Private Sub OSetMessage(ByRef text As Const String, ByVal kind As Integer = OUI_MSG_INFO)
    OUI.message = text
    OUI.messageKind = kind
    OUI.messageTime = Timer
End Sub

Private Function MinutesOf(ByVal index As Integer) As Integer
    Dim As Integer m(0 To 4) = {3, 5, 10, 15, 30}
    Return m(IIf(index < 0, 0, IIf(index > 4, 4, index)))
End Function

Private Function IncrementOf(ByVal index As Integer) As Integer
    Dim As Integer v(0 To 3) = {0, 2, 5, 10}
    Return v(IIf(index < 0, 0, IIf(index > 3, 3, index)))
End Function

Private Function Feature_Guests() As Boolean
    Return Online_Feature("guests")
End Function

Private Function ValidNickname(ByRef nick As Const String) As Boolean
    If Len(nick) < 3 OrElse Len(nick) > 16 Then Return False
    Dim As Integer k
    For k = 0 To Len(nick) - 1
        Dim As Integer c = nick[k]
        If Not ((c >= 48 AndAlso c <= 57) OrElse (c >= 65 AndAlso c <= 90) OrElse (c >= 97 AndAlso c <= 122) _
                OrElse c = 95) Then Return False
    Next
    Return True
End Function

'' A player name in a list, with "(you)" for oneself, made to fit into maxW pixels.
Private Sub DrawListName(ByVal x As Integer, ByVal y As Integer, ByVal maxW As Integer, ByRef nm As Const String, _
                         ByVal isMe As Boolean, ByVal colour As ULong)
    Dim As String s = nm & IIf(isMe, "  (you)", "")
    Dim As Integer size = 17
    If Text_Width(s, size) > maxW Then s = nm & IIf(isMe, " (you)", "")
    Do While Text_Width(s, size) > maxW AndAlso size > 13
        size -= 1
    Loop
    Text_Draw(x, y + (17 - size) \ 2, s, size, colour)
End Sub

Private Function ClockText(ByVal ms As LongInt) As String
    If ms < 0 Then ms = 0
    Dim As LongInt totalSec = (ms + 999) \ 1000
    If ms < 10000 Then                                    '' tenths in the last ten seconds
        Return "0:" & Right("0" & (ms \ 1000), 2) & "." & ((ms Mod 1000) \ 100)
    End If
    Return (totalSec \ 60) & ":" & Right("0" & (totalSec Mod 60), 2)
End Function

'' ---------------------------------------------------------------------
'' Entering the online area
'' ---------------------------------------------------------------------
Sub Online_Enter()
    OUI.message = ""
    OUI.lobbyScroll = 0
    Dim As Integer st = Online_Status()
    If st = OL_OFFLINE OrElse st = OL_LOST Then
        Dim As String e
        If Not Online_Connect(AppConfig.onlineServer, e) Then OSetMessage(e, OUI_MSG_BAD)
        OUI.subscribed = False
    End If
End Sub

Private Sub OpenGuestDialog()
    InputDialog_Open(OUI.nameDlg, "nick", "Play as guest", _
                     "Your nickname (3-16 letters, digits or _). Other players see it as Guest_<name>. " & _
                     "Guest games are not saved.", AppConfig.onlineNickname, "Play|Cancel", 16)
End Sub

Private Sub OpenCredDialog(ByRef id As Const String, ByRef title As Const String, ByRef prompt As Const String, _
                           ByRef initial As Const String, ByRef buttons As Const String, ByVal masked As Boolean, _
                           ByRef errText As Const String = "")
    InputDialog_Open(OUI.credDlg, id, title, prompt, initial, buttons, IIf(masked, 128, 16))
    OUI.credDlg.masked = masked
    OUI.credDlg.errorText = errText
End Sub

Private Function ValidUsername(ByRef u As Const String) As Boolean
    Return ValidNickname(u) AndAlso LCase(Left(u, 5)) <> "guest"
End Function

Private Sub StartLogin(ByRef errText As Const String = "")
    OpenCredDialog("user", "Log in", "Your user name:", AppConfig.onlineUser, "Next|Cancel", False, errText)
End Sub

Private Sub StartRegister(ByRef errText As Const String = "")
    OpenCredDialog("ruser", "New account", _
                   "Choose a user name (3-16 letters, digits or _; it may not start with Guest). " & _
                   "No e-mail or real name is needed.", OUI.flowUser, "Next|Cancel", False, errText)
End Sub

'' Called when the server greeted us: log in again with a remembered token.
Private Sub TryResume()
    Dim As String tok = Token_Load(Online_ServerHost())
    If tok <> "" Then
        Online_Resume(tok)
        OSetMessage("Logging in...", OUI_MSG_INFO)
    End If
End Sub

Sub Online_ShowProfile(ByRef username As Const String)
    OUI.profileName = username
    OUI.histOffset = 0
    Dim As OnlineProfile Ptr pr = Online_Profile()
    pr->valid = False
    Online_RequestProfile(username)
    If username = "" Then Online_RequestHistory(0)
End Sub

Private Sub StartGuestLogin()
    If Not ValidNickname(AppConfig.onlineNickname) Then
        InputDialog_Open(OUI.nameDlg, "nick", "Your nickname", _
                         "Choose a nickname for online games (3-16 letters, digits or _). Other players see it as Guest_<name>.", _
                         AppConfig.onlineNickname, "Play|Cancel", 16)
        Exit Sub
    End If
    If Online_Status() = OL_READY Then
        Online_LoginGuest(AppConfig.onlineNickname)
        OSetMessage("Logging in...", OUI_MSG_INFO)
    Else
        OUI.wantLogin = True
    End If
End Sub

'' ---------------------------------------------------------------------
'' Game helpers
'' ---------------------------------------------------------------------
Private Function OpponentColor() As String
    Return IIf(Online_Game()->myColor = "w", "b", "w")
End Function

Private Function NameOf(ByRef colour As Const String) As String
    Dim As OnlineGame Ptr g = Online_Game()
    Return IIf(colour = "w", g->whiteName, g->blackName)
End Function

Private Function RatingOf(ByRef colour As Const String) As Integer
    Dim As OnlineGame Ptr g = Online_Game()
    Return IIf(colour = "w", g->whiteRating, g->blackRating)
End Function

Private Function TerminationText(ByRef t As Const String) As String
    Select Case t
    Case "checkmate" : Return "by checkmate"
    Case "resignation" : Return "by resignation"
    Case "timeout" : Return "on time"
    Case "timeout_vs_insufficient_material" : Return "time ran out, but the other side could not have won"
    Case "stalemate" : Return "by stalemate"
    Case "insufficient_material" : Return "nobody can checkmate any more"
    Case "fivefold_repetition" : Return "the same position five times"
    Case "seventyfive_moves" : Return "75 moves without a capture or pawn move"
    Case "threefold_repetition" : Return "the same position three times (claimed)"
    Case "fifty_moves" : Return "50 moves without a capture or pawn move (claimed)"
    Case "agreement" : Return "by agreement"
    Case "first_move_timeout" : Return "a first move was not made in time"
    Case "aborted_by_player" : Return "the game was cancelled"
    Case "abandoned" : Return "a player left the game"
    Case "server_restart" : Return "the server restarted before the game could continue"
    Case Else : Return t
    End Select
End Function

'' "You won!", "You lost", "Draw" or "Game cancelled" plus the reason.
Private Function ResultText(ByRef title As String) As String
    Dim As OnlineGame Ptr g = Online_Game()
    If g->status = "aborted" Then
        title = "Game cancelled"
        If g->termination = "aborted_by_player" Then Return "No result."
        Return "No result: " & TerminationText(g->termination) & "."
    End If
    If g->result = "1/2-1/2" Then
        title = "Draw"
    ElseIf (g->result = "1-0") = (g->myColor = "w") Then
        title = "You won!"
    Else
        title = "You lost"
    End If
    Dim As String r = TerminationText(g->termination)
    Return UCase(Left(r, 1)) & Mid(r, 2) & "."
End Function

'' Loads the server position into the board (after a reload or a new game).
Private Sub ShowServerPosition()
    Dim As OnlineGame Ptr g = Online_Game()
    Dim As String e
    If g->fen = "" OrElse Not Pos_LoadFEN(OUI.pos, g->fen, e) Then Pos_LoadFEN(OUI.pos, START_FEN, e)
    OUI.shownPly = g->ply
    OUI.pendingMove = ""
    BC_Reset(OnlineBC)
    If g->ply > 0 Then
        Dim As String u = g->moves(g->ply - 1)
        OnlineBC.lastFrom = Sq_Parse(Left(u, 2))
        OnlineBC.lastTo = Sq_Parse(Mid(u, 3, 2))
    End If
End Sub

Private Function SameBoard(ByRef a As Const String, ByRef b As Const String) As Boolean
    '' Placement and side to move (the counters/en passant field may be written differently).
    Dim As Integer sa = InStr(InStr(a, " ") + 1, a, " "), sb = InStr(InStr(b, " ") + 1, b, " ")
    Return sa > 0 AndAlso sb > 0 AndAlso Left(a, sa) = Left(b, sb)
End Function

'' Brings the board up to date with the server's game.
Private Sub SyncBoard()
    Dim As OnlineGame Ptr g = Online_Game()
    If Not g->active Then Exit Sub
    If g->gameId <> OUI.gameId Then
        OUI.gameId = g->gameId
        OUI.flipped = (g->myColor = "b")
        OUI.overlayClosed = False
        OUI.endHandled = False
        OUI.listScroll = 0
        ShowServerPosition()
        Exit Sub
    End If
    If g->ply = OUI.shownPly Then Exit Sub
    If g->ply = OUI.shownPly + 1 Then
        Dim As String u = g->moves(g->ply - 1)
        If OUI.pendingMove <> "" AndAlso u = OUI.pendingMove Then
            '' Our own move confirmed: it is already on the board.
            OUI.pendingMove = ""
            OUI.shownPly = g->ply
            If Not SameBoard(Pos_GetFEN(OUI.pos), g->fen) Then ShowServerPosition()
            Exit Sub
        End If
        If OUI.pendingMove = "" Then
            '' The opponent's move: animate it from the current position.
            Dim As ChessMove m
            Dim As String e
            If Notation_ParseUCI(OUI.pos, u, m, e) Then
                Pos_MakeMove(OUI.pos, m)
                If SameBoard(Pos_GetFEN(OUI.pos), g->fen) Then
                    BC_AnimateMove(OnlineBC, OUI.pos, m)
                    OUI.shownPly = g->ply
                    Exit Sub
                End If
            End If
        End If
    End If
    ShowServerPosition()                                   '' anything else: show the server's truth
End Sub

Private Function StartReview() As Boolean
    Dim As OnlineGame Ptr g = Online_Game()
    Dim As String e
    Game_New(ReviewGame)
    Dim As Integer k
    For k = 0 To g->ply - 1
        If Not Game_PlayMoveText(ReviewGame, g->moves(k), e) Then Return False
    Next
    Review_Start(ReviewGame, SCREEN_ONLINE_GAME, OUI.flipped)
    Return True
End Function

Private Sub SaveGamePgn()
    Dim As OnlineGame Ptr g = Online_Game()
    If g->pgn = "" Then Exit Sub
    If Not Save_EnsureDirectory() Then
        OSetMessage("The folder for saved games could not be created.", OUI_MSG_BAD)
        Exit Sub
    End If
    Dim As String d = Date(), t = Time()
    Dim As String fileName = Save_Directory() & "/Online_" & Mid(d, 7, 4) & Left(d, 2) & Mid(d, 4, 2) & "_" & _
                             Left(t, 2) & Mid(t, 4, 2) & Right(t, 2) & ".pgn"
    If Pgn_WriteFile(fileName, g->pgn) Then
        OSetMessage("Game saved as " & fileName, OUI_MSG_GOOD)
    Else
        OSetMessage("The game could not be saved.", OUI_MSG_BAD)
    End If
End Sub

'' ---------------------------------------------------------------------
'' Event pump (every frame, every screen)
'' ---------------------------------------------------------------------
Function OnlineUI_Pump(ByVal currentScreen As Integer) As Integer
    Online_Update(Timer)
    Dim As OnlineEvent ev
    Dim As OnlineGame Ptr g = Online_Game()
    Do While Online_NextEvent(ev)
        Select Case ev.kind
        Case "welcome"
            OUI.subscribed = False
            If OUI.wantLogin Then
                OUI.wantLogin = False
                StartGuestLogin()
            Else
                TryResume()
            End If
        Case "logged_in"
            If Online_MyKind() = "account" Then
                AppConfig.onlineUser = Online_MyName()
                Settings_Save(AppConfig, Settings_FileName())
                If OUI.remember Then
                    If Not Token_Save(Online_ServerHost(), Online_SessionToken()) Then
                        UI_ShowToast("Note", "Could not remember the login")
                    End If
                End If
            End If
            OUI.remember = False
            If Not (g->active AndAlso g->status = "active") Then          '' (a reconnect continues the game)
                OSetMessage("Welcome, " & Online_MyName() & "! Choose a time control and find an opponent.", OUI_MSG_GOOD)
                Online_LobbySubscribe()
                OUI.subscribed = True
            End If
        Case "matchmaking_found"
            UI_ShowToast("Opponent found", "The game starts now!")
        Case "game_started"
            Audio_Play(SND_START)
            If OUI.subscribed Then Online_LobbyUnsubscribe() : OUI.subscribed = False
            OUI.gameId = ""                                '' SyncBoard sets up the new game
            SyncBoard()
            currentScreen = SCREEN_ONLINE_GAME
            OSetMessage("You play " & IIf(g->myColor = "w", "White", "Black") & " against " & _
                        NameOf(OpponentColor()) & ". Good luck!", OUI_MSG_GOOD)
        Case "game_resumed"
            If OUI.subscribed Then Online_LobbyUnsubscribe() : OUI.subscribed = False
            SyncBoard()
            If g->status = "active" Then
                currentScreen = SCREEN_ONLINE_GAME
                OSetMessage("Back in the game!", OUI_MSG_GOOD)
            End If
        Case "reconnecting"
            OSetMessage("Connection lost - reconnecting...", OUI_MSG_BAD)
        Case "opponent_disconnected"
            OSetMessage(NameOf(OpponentColor()) & " lost the connection. Waiting for them to come back...", OUI_MSG_INFO)
        Case "opponent_reconnected"
            OSetMessage(NameOf(OpponentColor()) & " is back.", OUI_MSG_GOOD)
        Case "rating_update"
            If g->myBefore >= 0 Then
                Dim As Integer delta = g->myAfter - g->myBefore
                UI_ShowToast("Online rating", g->myBefore & " -> " & g->myAfter & " (" & IIf(delta >= 0, "+", "") & delta & ")")
            End If
        Case "challenge_received"
            Audio_Play(SND_CHECK)
        Case "challenge_declined"
            OSetMessage("Your challenge was declined.", OUI_MSG_INFO)
        Case "challenge_expired"
            OSetMessage("A challenge expired (no answer within a minute).", OUI_MSG_INFO)
        Case "challenge_cancelled"
            Dim As JsonDoc cd
            Dim As String cerr
            Json_Parse(cd, ev.text, cerr)
            Dim As String why = Json_GetStr(cd, 0, "reason")
            OSetMessage(IIf(why = "busy", "A challenge ended: the player started another game.", _
                            IIf(why = "left", "A challenge ended: the player left.", "A challenge was taken back.")), _
                        OUI_MSG_INFO)
        Case "challenge_sent"
            OSetMessage("Challenge sent. It stays open for one minute.", OUI_MSG_INFO)
        Case "draw_offered"
            Audio_Play(SND_CLICK)
            OSetMessage(NameOf(OpponentColor()) & " offers a draw.", OUI_MSG_INFO)
        Case "draw_declined"
            OSetMessage(NameOf(OpponentColor()) & " declined the draw offer.", OUI_MSG_INFO)
        Case "game_over"
            SyncBoard()
        Case "logged_out"
            OUI.subscribed = False
            OSetMessage("You are logged out.", OUI_MSG_INFO)
        Case "account_deleted"
            Token_Delete(Online_ServerHost())
            OUI.subscribed = False
            OSetMessage("Your account has been deleted.", OUI_MSG_INFO)
            If currentScreen = SCREEN_ONLINE_PROFILE Then currentScreen = SCREEN_ONLINE
        Case "session_replaced"
            OUI.subscribed = False
            OSetMessage(ev.message, OUI_MSG_BAD)
        Case "game_record"
            Dim As JsonDoc d
            Dim As String perr
            If Json_Parse(d, ev.text, perr) Then
                Dim As String pgnText = Json_GetStr(d, Json_Member(d, 0, "game"), "pgn")
                If pgnText <> "" AndAlso Viewer_StartPgn(pgnText, SCREEN_ONLINE_PROFILE, perr) Then
                    currentScreen = SCREEN_VIEWER
                Else
                    OSetMessage("This game cannot be replayed.", OUI_MSG_BAD)
                End If
            End If
        Case "error"
            Select Case ev.requestType
            Case "login_guest"
                OSetMessage(ev.message, OUI_MSG_BAD)
                OpenGuestDialog()
                OUI.nameDlg.errorText = ev.message
            Case "resume"
                Token_Delete(Online_ServerHost())          '' expired or revoked: forget it
                OSetMessage("Please log in again.", OUI_MSG_INFO)
            Case "login"
                OpenCredDialog("user", "Log in", "Your user name:", AppConfig.onlineUser, "Next|Cancel", False, ev.message)
            Case "register"
                StartRegister(ev.message)
            Case "delete_account"
                OSetMessage(ev.message, OUI_MSG_BAD)
            Case "move"
                OUI.pendingMove = ""
                ShowServerPosition()
                If ev.code = "illegal_move" Then
                    OSetMessage("The server did not accept that move.", OUI_MSG_BAD)
                ElseIf ev.code <> "game_over" Then
                    OSetMessage("The game had moved on - the board is up to date again.", OUI_MSG_INFO)
                End If
            Case Else
                OSetMessage(ev.message, OUI_MSG_BAD)
            End Select
        Case "request_timeout"
            If ev.requestType = "move" Then
                '' Safe to resend: the server never plays a move twice.
                If OUI.pendingMove <> "" Then Online_SendMove(OUI.pendingMove)
            Else
                OSetMessage("The server did not answer in time.", OUI_MSG_BAD)
            End If
        Case "server_shutdown"
            OSetMessage(ev.message, OUI_MSG_BAD)
        Case "connection_lost", "connection_closed"
            OUI.subscribed = False
            OSetMessage(ev.message, OUI_MSG_BAD)
            If currentScreen = SCREEN_ONLINE_GAME AndAlso g->status = "active" Then
                Audio_Play(SND_ILLEGAL)
            End If
        End Select
    Loop
    '' Incoming challenges are shown on the online screens (never over a running game).
    Dim As Boolean onlineScreen = (currentScreen = SCREEN_ONLINE OrElse currentScreen = SCREEN_ONLINE_PROFILE _
                                   OrElse currentScreen = SCREEN_ONLINE_LEADERBOARD)
    If OUI.chDlg.active Then
        Dim As Boolean stillOpen = False
        Dim As Integer ci
        For ci = 0 To Online_IncomingCount() - 1
            If Online_Incoming(ci)->challengeId = OUI.chDlgId Then stillOpen = True
        Next
        If Not stillOpen OrElse Not onlineScreen Then
            OUI.chDlg.active = False                         '' expired, taken back - or we left
        Else
            Dim As Integer r = Dialog_Run(OUI.chDlg)
            If r = 0 Then Online_ChallengeAccept(OUI.chDlgId)
            If r = 1 Then Online_ChallengeDecline(OUI.chDlgId)
        End If
    ElseIf onlineScreen AndAlso Online_IncomingCount() > 0 AndAlso Not (g->active AndAlso g->status = "active") Then
        Dim As OnlineChallenge Ptr ch = Online_Incoming(0)
        OUI.chDlgId = ch->challengeId
        Dialog_Open(OUI.chDlg, "challenge", "Challenge!", _
                    ch->playerName & IIf(ch->rating >= 0, " (" & ch->rating & ")", "") & " challenges you to a " & _
                    IIf(ch->rated, "rated", "casual") & " game: " & ch->minutes & " minutes" & _
                    IIf(ch->increment > 0, " + " & ch->increment & " seconds per move", "") & ".", "Accept|Decline")
    End If
    If g->active Then
        SyncBoard()
        '' Result sound and statistics once per game.
        If g->status <> "active" AndAlso Not OUI.endHandled AndAlso g->gameId = OUI.gameId Then
            OUI.endHandled = True
            If g->status = "aborted" OrElse g->result = "1/2-1/2" Then
                Audio_Play(SND_DRAW)
            ElseIf (g->result = "1-0") = (g->myColor = "w") Then
                Audio_Play(SND_VICTORY)
            Else
                Audio_Play(SND_DEFEAT)
            End If
        End If
    End If
    Return currentScreen
End Function

'' ---------------------------------------------------------------------
'' Online home screen
'' ---------------------------------------------------------------------
Private Sub StatusDot(ByVal x As Integer, ByVal y As Integer)
    Dim As ULong c
    Select Case Online_Status()
    Case OL_READY : c = RGB(60, 170, 80)
    Case OL_CONNECTING, OL_HANDSHAKE : c = RGB(230, 170, 40)
    Case Else : c = RGB(200, 70, 60)
    End Select
    Gfx_FillCircle(x, y, 7, c)
End Sub

Private Sub RunCredDialog()
    Dim As Integer r = InputDialog_Run(OUI.credDlg)
    If r < 0 Then Exit Sub
    Dim As String id = OUI.credDlg.id, text = OUI.credDlg.text
    Dim As Integer lastButton = UI_OptionCount(OUI.credDlg.buttons) - 1
    If r = lastButton Then                                    '' Cancel
        OUI.credDlg.active = False
        OUI.flowPass = ""
        Exit Sub
    End If
    Select Case id
    Case "user"
        If Not ValidUsername(Trim(text)) Then
            OUI.credDlg.errorText = "User names have 3-16 letters, digits or _."
            Exit Sub
        End If
        OUI.flowUser = Trim(text)
        OpenCredDialog("pass", "Log in", "Password for " & OUI.flowUser & ":", "", _
                       "Log in|Log in and remember me|Cancel", True)
    Case "pass"
        If Len(text) = 0 Then Exit Sub
        OUI.remember = (r = 1)
        OUI.credDlg.active = False
        Online_Login(OUI.flowUser, text)
        OUI.credDlg.text = ""
        OSetMessage("Logging in...", OUI_MSG_INFO)
    Case "ruser"
        If Not ValidUsername(Trim(text)) Then
            OUI.credDlg.errorText = "Use 3-16 letters, digits or _ (not starting with Guest)."
            Exit Sub
        End If
        OUI.flowUser = Trim(text)
        OpenCredDialog("rpass", "New account", "Choose a password (8 or more characters). There is no e-mail, " & _
                       "so a forgotten password cannot be recovered - please write it down somewhere safe.", _
                       "", "Next|Cancel", True)
    Case "rpass"
        If Len(text) < 8 Then
            OUI.credDlg.errorText = "At least 8 characters, please."
            Exit Sub
        End If
        If LCase(text) = LCase(OUI.flowUser) Then
            OUI.credDlg.errorText = "The password must be different from the user name."
            Exit Sub
        End If
        OUI.flowPass = text
        OpenCredDialog("rpass2", "New account", "Type the password again:", "", _
                       "Create account|Create and remember me|Cancel", True)
    Case "rpass2"
        If text <> OUI.flowPass Then
            OUI.flowPass = ""
            OpenCredDialog("rpass", "New account", "The two passwords were different. Choose a password again:", _
                           "", "Next|Cancel", True)
            Exit Sub
        End If
        OUI.remember = (r = 1)
        OUI.credDlg.active = False
        Online_Register(OUI.flowUser, text)
        OUI.flowPass = ""
        OUI.credDlg.text = ""
        OSetMessage("Creating your account...", OUI_MSG_INFO)
    Case "delpass"
        OUI.credDlg.active = False
        Online_DeleteAccount(text)
        OUI.credDlg.text = ""
    End Select
End Sub

Function Online_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_ONLINE
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    UI.blockInput = OUI.nameDlg.active OrElse OUI.serverDlg.active OrElse OUI.dlg.active OrElse OUI.credDlg.active _
                    OrElse OUI.chDlg.active
    UI_DrawBackground()
    Screen_DrawHeader("Play Online")
    If CBool(Online_Status() = OL_CONNECTING) OrElse CBool(Online_Status() = OL_HANDSHAKE) OrElse Online_Waiting() Then UI_KeepFast(0.5)

    Dim As Integer lx = 24, lw = 470, y = 62
    Dim As ULong ink = RGB(50, 44, 36), soft = RGB(120, 105, 90)
    Dim As Integer st = Online_Status()
    Dim As Boolean ready = (st = OL_READY)

    '' ---- Connection
    Gfx_Panel(lx, y, lw, 128, 14, RGB(252, 249, 240), RGB(150, 120, 80))
    Text_Draw(lx + 16, y + 10, "Server", 20, RGB(80, 52, 24))
    StatusDot(lx + 24, y + 48)
    Dim As String stText = Online_StatusText()
    If st = OL_OFFLINE AndAlso stText = "Not connected" Then stText = "Not connected."
    Dim As Integer sts = Text_FitSize(stText, lw - 60, 34, 18, 12)          '' keep clear of the address line
    Text_DrawWrapped(lx + 40, y + 38, lw - 60, stText, sts, IIf(st = OL_LOST, RGB(170, 50, 40), ink))
    Text_Draw(lx + 16, y + 74, Left(AppConfig.onlineServer, 52), 14, soft)
    If ready OrElse st = OL_CONNECTING OrElse st = OL_HANDSHAKE Then
        If UI_Button("ol.disc", lx + 16, y + 92, 150, 30, "Disconnect", True, "Leave the online area's connection.") Then
            Online_Disconnect()
            OUI.subscribed = False
        End If
    ElseIf UI_Button("ol.conn", lx + 16, y + 92, 150, 30, "Connect", True, "Connect to the server.", BTN_PRIMARY) Then
        Online_Enter()
    End If
    If UI_Button("ol.server", lx + 176, y + 92, 170, 30, "Server address...", True, _
                 "Play on another BeginnerChess server (advanced). Accounts and ratings belong to each server.") Then
        InputDialog_Open(OUI.serverDlg, "server", "Server address", _
                         "Address of a BeginnerChess server (wss://...). The default is " & ONLINE_SERVER_DEFAULT & _
                         ". Secure connections are always checked.", AppConfig.onlineServer, "Save|Default|Cancel", 256)
    End If
    y += 140

    '' ---- Player
    Gfx_Panel(lx, y, lw, 112, 14, RGB(252, 249, 240), RGB(150, 120, 80))
    Text_Draw(lx + 16, y + 10, "You", 20, RGB(80, 52, 24))
    Dim As Integer b3 = (lw - 32 - 16) \ 3
    If Online_LoggedIn() Then
        Dim As Boolean isAccount = (Online_MyKind() = "account")
        Dim As String who = "Playing as " & Online_MyName()
        If isAccount Then who &= "  -  rating " & Online_MyRating() & IIf(Online_MyProvisional(), "?", "")
        Text_Draw(lx + 16, y + 40, who, 20, RGB(30, 110, 50))
        Text_Draw(lx + 16, y + 64, IIf(isAccount, "Your online games are saved in your history.", _
                                         "Guest games are casual: no rating, no history."), 15, soft)
        If isAccount Then
            If UI_Button("ol.prof", lx + 16, y + 82, b3, 26, "My profile", True, "Your statistics and match history.") Then
                Online_ShowProfile("")
                nextScreen = SCREEN_ONLINE_PROFILE
            End If
        End If
        If UI_Button("ol.logout", lx + 16 + IIf(isAccount, b3 + 8, 0), y + 82, b3, 26, "Log out", Not Online_Waiting(), _
                     "Log out (a remembered login is forgotten).") Then
            Online_Logout()
            Token_Delete(Online_ServerHost())
        End If
    Else
        Text_DrawWrapped(lx + 16, y + 38, lw - 32, "Play as a guest, or log in to keep your games.", 17, ink)
        If UI_Button("ol.guest", lx + 16, y + 72, b3, 30, "Play as guest", ready AndAlso Feature_Guests(), _
                     "Play with a nickname - no account needed.", BTN_PRIMARY) Then
            OpenGuestDialog()
        End If
        If UI_Button("ol.login", lx + 24 + b3, y + 72, b3, 30, "Log in", ready, "Log in to your account.") Then
            StartLogin()
        End If
        If UI_Button("ol.register", lx + 32 + 2 * b3, y + 72, b3, 30, "New account", ready AndAlso Online_Feature("registration"), _
                     "Create a free account (user name and password only).") Then
            OUI.flowUser = ""
            StartRegister()
        End If
    End If
    y += 124

    '' ---- Quick match
    Gfx_Panel(lx, y, lw, 238, 14, RGB(252, 249, 240), RGB(150, 120, 80))
    Text_Draw(lx + 16, y + 10, "Quick match", 20, RGB(80, 52, 24))
    Dim As Boolean canRate = (Online_MyKind() = "account") AndAlso Online_Feature("rated_games")
    If Not canRate Then OUI.rated = 0
    Dim As Boolean canChoose = Online_LoggedIn() AndAlso Not Online_Waiting()
    Text_Draw(lx + 16, y + 48, "Time:", 18, ink)
    If UI_Selector("ol.min", lx + 120, y + 40, lw - 136, 36, MINUTE_OPTIONS, AppConfig.onlineMinutes, canChoose, _
                   "Thinking time for each player.") Then Settings_Save(AppConfig, Settings_FileName())
    Text_Draw(lx + 16, y + 92, "Bonus:", 18, ink)
    If UI_Selector("ol.inc", lx + 120, y + 84, lw - 136, 36, INCREMENT_OPTIONS, AppConfig.onlineIncrement, canChoose, _
                   "Extra seconds added to your clock after each of your moves.") Then Settings_Save(AppConfig, Settings_FileName())
    Text_Draw(lx + 16, y + 136, "Game:", 18, ink)
    UI_Selector("ol.rated", lx + 120, y + 128, lw - 136, 36, "casual (no rating)|rated", OUI.rated, _
                canChoose AndAlso canRate, IIf(canRate, "Rated games change your online rating.", _
                                                "Rated games are for registered players (New account)."))
    If Online_Waiting() Then
        Dim As String dots = String(1 + (Int(Timer * 2) Mod 3), ".")
        Text_Draw(lx + 16, y + 188, "Looking for an opponent" & dots, 20, RGB(40, 80, 160))
        If UI_Button("ol.cancel", lx + lw - 136, y + 180, 120, 38, "Cancel", True, "Stop looking.") Then
            Online_CancelMatch()
        End If
    ElseIf UI_Button("ol.find", lx + 16, y + 178, lw - 32, 44, "Find an opponent", Online_LoggedIn(), _
                     IIf(Online_LoggedIn(), "Play the next player who wants the same kind of game.", _
                         "Log in first (Play as guest)."), BTN_PRIMARY) Then
        Online_QuickMatch(MinutesOf(AppConfig.onlineMinutes), IncrementOf(AppConfig.onlineIncrement), OUI.rated = 1)
    End If
    y += 250

    '' ---- Our open challenge
    Dim As OnlineChallenge Ptr outC = Online_Outgoing()
    If outC->challengeId <> "" AndAlso Online_LoggedIn() Then
        Gfx_Panel(lx, y, lw, 48, 12, RGB(230, 240, 255), RGB(52, 120, 206), False)
        Text_Draw(lx + 12, y + 14, "Challenge sent to " & Left(outC->playerName, 18) & " - waiting...", 17, RGB(30, 60, 130))
        If UI_Button("ol.chcancel", lx + lw - 100, y + 8, 88, 32, "Cancel", True, "Take the challenge back.") Then
            Online_ChallengeCancel(outC->challengeId)
        End If
        y += 56
    End If

    '' ---- Fair play note / messages
    Dim As String note = "Online games are real games: no hints, no take-backs and no computer help. " & _
                         "Please be friendly and play fair!"
    If OUI.message <> "" AndAlso Timer - OUI.messageTime < 8 Then
        Dim As ULong mc = IIf(OUI.messageKind = OUI_MSG_BAD, RGB(255, 200, 190), _
                              IIf(OUI.messageKind = OUI_MSG_GOOD, RGB(200, 245, 200), RGB(220, 230, 245)))
        Text_DrawWrapped(lx + 4, y, lw - 8, OUI.message, 18, mc)
    Else
        Text_DrawWrapped(lx + 4, y, lw - 8, note, 16, RGB(200, 210, 225))
    End If

    '' ---- Players online
    Dim As Integer rx = lx + lw + 20, rw = sw - rx - 24, ry = 62, rh = sh - ry - 84
    Gfx_Panel(rx, ry, rw, rh, 14, RGB(255, 255, 255), RGB(150, 120, 80))
    Text_Draw(rx + 16, ry + 10, "Players online" & IIf(Online_LoggedIn(), " (" & Online_LobbyTotal() & ")", ""), _
              20, RGB(80, 52, 24))
    If Not Online_LoggedIn() Then
        Text_DrawWrapped(rx + 16, ry + 48, rw - 32, "Log in (Play as guest) to see who is online.", 18, soft)
    Else
        Dim As Integer rowH = 30, visible = (rh - 50) \ rowH, k
        If UI_Hover(rx, ry, rw, rh) AndAlso UI.wheelDelta <> 0 Then OUI.lobbyScroll -= UI.wheelDelta * 3
        If OUI.lobbyScroll > Online_LobbyCount() - visible Then OUI.lobbyScroll = Online_LobbyCount() - visible
        If OUI.lobbyScroll < 0 Then OUI.lobbyScroll = 0
        For k = 0 To visible - 1
            Dim As OnlineLobbyEntry Ptr e = Online_LobbyEntry(OUI.lobbyScroll + k)
            If e = 0 Then Exit For
            Dim As Integer yy = ry + 46 + k * rowH
            If (k Mod 2) = 0 Then Gfx_FillRect(rx + 8, yy - 3, rw - 16, rowH, RGB(246, 242, 232))
            Dim As Boolean isMe = (e->playerName = Online_MyName())
            If e->kind = "account" AndAlso UI_Hover(rx + 8, yy - 3, rw - 320, rowH) Then
                Gfx_FillRect(rx + 8, yy - 3, rw - 320, rowH, RGBA(52, 120, 206, 40))
                UI_SetTooltip("ol.row" & k, "Show " & e->playerName & "'s profile.")
                If UI.released Then
                    Online_ShowProfile(e->playerName)
                    nextScreen = SCREEN_ONLINE_PROFILE
                End If
            End If
            DrawListName(rx + 16, yy + 2, rw - 330, Left(e->playerName, 22), isMe, IIf(isMe, RGB(30, 110, 50), ink))
            Text_Draw(rx + rw - 300, yy + 2, IIf(e->rating >= 0, Str(e->rating), IIf(e->kind = "guest", "guest", "")), 16, soft)
            Dim As String stx = IIf(e->status = "available", "available", IIf(e->status = "waiting", "looking", "playing"))
            Dim As ULong sc = IIf(e->status = "available", RGB(40, 140, 60), IIf(e->status = "waiting", RGB(40, 90, 170), RGB(140, 130, 120)))
            Text_Draw(rx + rw - 210, yy + 2, stx, 15, sc)
            If Not isMe AndAlso e->status <> "playing" Then
                Dim As Boolean ratedCh = (OUI.rated = 1) AndAlso e->kind = "account"
                If UI_Button("ol.ch" & k, rx + rw - 112, yy - 1, 96, 24, "Challenge", _
                             outC->challengeId = "" AndAlso Not Online_Waiting(), _
                             "Invite " & e->playerName & " to a " & IIf(ratedCh, "rated", "casual") & " game (" & _
                             MinutesOf(AppConfig.onlineMinutes) & "+" & IncrementOf(AppConfig.onlineIncrement) & ").") Then
                    Online_Challenge(e->playerName, MinutesOf(AppConfig.onlineMinutes), _
                                     IncrementOf(AppConfig.onlineIncrement), ratedCh)
                End If
            End If
        Next
        If Online_LobbyCount() = 0 Then Text_Draw(rx + 16, ry + 48, "Nobody else is online right now.", 18, soft)
    End If

    '' ---- Back, leaderboard
    If UI_Button("ol.leaders", 180, sh - 64, 170, 46, "Leaderboard", Online_LoggedIn(), _
                 "The best rated players on this server.") Then
        OUI.leaderOffset = 0
        Online_RequestLeaderboard(0)
        nextScreen = SCREEN_ONLINE_LEADERBOARD
    End If
    Dim As Boolean goBack = UI_Button("ol.back", 20, sh - 64, 140, 46, "< Back", True, _
                                      "Leave the online area (disconnects).")
    If UI.keyCode = KEY_ESCAPE AndAlso Not UI.blockInput Then goBack = True
    If goBack Then
        If Online_Waiting() Then Online_CancelMatch()
        Online_Disconnect()
        OUI.subscribed = False
        nextScreen = SCREEN_MENU
    End If

    '' ---- Dialogs
    If OUI.nameDlg.active Then
        Dim As Integer r = InputDialog_Run(OUI.nameDlg)
        If r = 0 Then
            Dim As String nick = Trim(OUI.nameDlg.text)
            If ValidNickname(nick) Then
                AppConfig.onlineNickname = nick
                Settings_Save(AppConfig, Settings_FileName())
                OUI.nameDlg.active = False
                StartGuestLogin()
            Else
                OUI.nameDlg.errorText = "Use 3-16 letters, digits or _ (no spaces)."
            End If
        ElseIf r > 0 Then
            OUI.nameDlg.active = False
        End If
    End If
    If OUI.serverDlg.active Then
        Dim As Integer r = InputDialog_Run(OUI.serverDlg)
        If r = 0 OrElse r = 1 Then
            Dim As String url = IIf(r = 1, ONLINE_SERVER_DEFAULT, Trim(OUI.serverDlg.text))
            Dim As Boolean secure
            Dim As String host, path, e
            Dim As Integer port
            If Net_ParseUrl(url, secure, host, port, path, e) Then
                AppConfig.onlineServer = url
                Settings_Save(AppConfig, Settings_FileName())
                OUI.serverDlg.active = False
                Online_Disconnect()
                Online_Enter()
            Else
                OUI.serverDlg.errorText = e
            End If
        ElseIf r > 1 Then
            OUI.serverDlg.active = False
        End If
    End If
    If OUI.credDlg.active Then RunCredDialog()
    Return nextScreen
End Function

'' ---------------------------------------------------------------------
'' Online game screen
'' ---------------------------------------------------------------------
Private Sub DrawPlayerCard(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByRef colour As Const String, _
                           ByVal isMe As Boolean)
    Dim As OnlineGame Ptr g = Online_Game()
    Dim As Boolean toMove = (g->status = "active" AndAlso g->turn = colour)
    Gfx_Panel(x, y, w, 70, 12, IIf(toMove, RGB(255, 248, 220), RGB(250, 247, 240)), _
              IIf(toMove, RGB(210, 160, 60), RGB(150, 120, 80)), False)
    Gfx_FillCircle(x + 26, y + 35, 13, IIf(colour = "w", RGB(250, 250, 245), RGB(40, 40, 45)))
    Gfx_Ring(x + 26, y + 35, 13, 2, RGB(120, 110, 100))
    Dim As String nm = NameOf(colour) & IIf(isMe, " (you)", "")
    Dim As Integer rating = RatingOf(colour)
    Text_Draw(x + 50, y + 12, Left(nm, 24), 20, RGB(40, 34, 28))
    Text_Draw(x + 50, y + 42, IIf(rating >= 0, "Rating " & rating, "Guest"), 15, RGB(120, 105, 90))
    Dim As LongInt ms = Online_ClockMs(colour, Timer)
    Dim As String ct = ClockText(ms)
    Dim As Boolean running = toMove AndAlso g->running = colour
    Dim As ULong cc = IIf(running AndAlso ms < 20000, RGB(200, 40, 30), IIf(running, RGB(30, 30, 30), RGB(120, 115, 110)))
    Dim As Integer cw = Text_Width(ct, 30)
    If running Then Gfx_RoundRect(x + w - cw - 26, y + 14, cw + 16, 42, 8, RGB(255, 236, 170))
    Text_Draw(x + w - cw - 18, y + 20, ct, 30, cc)
End Sub

Private Sub DrawMoveList(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer)
    Dim As OnlineGame Ptr g = Online_Game()
    Gfx_Panel(x, y, w, h, 12, RGB(255, 255, 255), RGB(150, 120, 80), False)
    Dim As Integer rows = (g->ply + 1) \ 2, rowH = 22, visible = (h - 12) \ rowH
    If rows > visible Then OUI.listScroll = rows - visible Else OUI.listScroll = 0
    Dim As Integer r
    For r = 0 To visible - 1
        Dim As Integer mi = (OUI.listScroll + r) * 2
        If mi >= g->ply Then Exit For
        Dim As Integer yy = y + 6 + r * rowH
        Text_Draw(x + 10, yy, (OUI.listScroll + r + 1) & ".", 16, RGB(140, 125, 110))
        Text_Draw(x + 60, yy, g->sans(mi), 17, RGB(40, 34, 28))
        If mi + 1 < g->ply Then Text_Draw(x + 60 + (w - 70) \ 2, yy, g->sans(mi + 1), 17, RGB(40, 34, 28))
    Next
    If g->ply = 0 Then Text_Draw(x + 10, y + 8, "No moves yet.", 16, RGB(150, 140, 130))
End Sub

Function OnlineGame_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_ONLINE_GAME
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    Dim As OnlineGame Ptr g = Online_Game()
    If Not g->active Then Return SCREEN_ONLINE
    UI.blockInput = OUI.dlg.active
    UI_DrawBackground()
    Screen_DrawHeader("Online" & IIf(g->rated, " (rated)", "") & ": " & g->whiteName & " vs " & g->blackName)
    If g->status = "active" Then UI_KeepFast(0.5)                       '' smooth clocks
    Dim As Boolean active = (g->status = "active")
    Dim As Boolean connected = (Online_Status() = OL_READY)
    Dim As Boolean myTurn = active AndAlso g->turn = g->myColor AndAlso OUI.pendingMove = ""

    '' ---- Board (player's colour at the bottom)
    OnlineBoard.theme = AppConfig.boardTheme
    OnlineBoard.pieceSet = AppConfig.pieceSet
    OnlineBoard.showCoords = AppConfig.showCoordinates
    OnlineBoard.flipped = OUI.flipped
    Board_Layout(OnlineBoard, 0, 0, 10)
    Dim As Integer sq = (sh - 50 - 24 - 2 * OnlineBoard.margin) \ 8
    If sq * 8 + 2 * OnlineBoard.margin > sw - 400 - 48 Then sq = (sw - 400 - 48 - 2 * OnlineBoard.margin) \ 8
    Board_Layout(OnlineBoard, 0, 0, sq)
    Dim As Integer outer = Board_OuterSize(OnlineBoard)
    Board_Layout(OnlineBoard, 16, 50 + (sh - 50 - outer) \ 2, sq)
    Dim As BoardMarks extra
    Board_ClearMarks(extra)
    If Pos_InCheck(OUI.pos) Then extra.checkSq = OUI.pos.kingSq(OUI.pos.sideToMove)
    Dim As ChessMove m
    Dim As String illegal
    If BC_Frame(OnlineBC, OnlineBoard, OUI.pos, myTurn AndAlso connected AndAlso Not UI.blockInput, extra, m, illegal) Then
        Dim As String uci = Notation_MoveToUCI(m)
        If Online_SendMove(uci) <> "" Then
            OUI.pendingMove = uci
            Pos_MakeMove(OUI.pos, m)
            BC_AnimateMove(OnlineBC, OUI.pos, m)
        Else
            OSetMessage("Not connected - the move was not sent.", OUI_MSG_BAD)
        End If
    End If
    If illegal <> "" Then OSetMessage(illegal, OUI_MSG_BAD)

    '' ---- Side panel
    Dim As Integer px = 16 + outer + 20, pw = sw - px - 16, y = 58
    Dim As String meC = g->myColor, oppC = OpponentColor()
    DrawPlayerCard(px, y, pw, oppC, False)
    y += 78

    '' Status box
    Dim As String stText
    Dim As ULong stCol = RGB(50, 44, 36)
    Dim As Integer awaySec = IIf(g->opponentAway, CInt(Timer - g->awaySince), 0)
    Dim As Boolean canClaimGone = active AndAlso connected AndAlso g->opponentAway AndAlso awaySec >= g->graceSec
    If Not connected AndAlso active Then
        If Online_Reconnecting() Then
            stText = "Connection lost - reconnecting... Your game is kept on the server."
        Else
            stText = "Connection lost: " & Online_StatusText()
        End If
        stCol = RGB(170, 40, 30)
    ElseIf canClaimGone Then
        stText = NameOf(oppC) & " has not come back. You can claim the win, call it a draw - or keep waiting."
        stCol = RGB(40, 70, 130)
    ElseIf active AndAlso g->opponentAway Then
        stText = NameOf(oppC) & " lost the connection. Waiting " & (g->graceSec - awaySec) & " s for them to come back..."
        stCol = RGB(40, 70, 130)
    ElseIf Not active Then
        Dim As String title, reason = ResultText(title)
        stText = title & " - " & LCase(Left(reason, 1)) & Mid(reason, 2)
        If g->rated AndAlso g->myBefore >= 0 Then
            Dim As Integer delta = g->myAfter - g->myBefore
            stText &= " Rating " & g->myBefore & " -> " & g->myAfter & " (" & IIf(delta >= 0, "+", "") & delta & ")."
        End If
        stCol = RGB(30, 90, 30)
    ElseIf OUI.message <> "" AndAlso Timer - OUI.messageTime < 6 Then
        stText = OUI.message
        stCol = IIf(OUI.messageKind = OUI_MSG_BAD, RGB(170, 40, 30), IIf(OUI.messageKind = OUI_MSG_GOOD, RGB(30, 110, 50), RGB(40, 70, 130)))
    ElseIf OUI.pendingMove <> "" Then
        stText = "Sending your move..."
    ElseIf g->drawOffer = oppC Then
        stText = NameOf(oppC) & " offers a draw. Accept or decline below - or just make your move."
        stCol = RGB(40, 70, 130)
    ElseIf myTurn Then
        stText = "Your move." & IIf(g->inCheck, " You are in check!", "")
        If g->firstMoveMs >= 0 Then stText &= " Make your first move within " & (g->firstMoveMs \ 1000) & " seconds."
        If g->drawOffer = meC Then stText &= " (You offered a draw.)"
    Else
        stText = "Waiting for " & NameOf(oppC) & "..."
        If g->drawOffer = meC Then stText &= " You offered a draw."
    End If
    Gfx_Panel(px, y, pw, 84, 12, RGB(252, 249, 240), RGB(150, 120, 80), False)
    Dim As Integer ts = Text_FitSize(stText, pw - 24, 70, 19, 14)
    Text_DrawWrapped(px + 12, y + 8, pw - 24, stText, ts, stCol)
    y += 92

    '' Buttons area (from the bottom)
    Dim As Integer bh = 40, gap = 8, bw = (pw - gap) \ 2
    Dim As Integer by2 = sh - 16 - bh, by1 = by2 - bh - gap
    Dim As Integer cardY = by1 - 10 - 70
    DrawMoveList(px, y, pw, cardY - 8 - y)
    DrawPlayerCard(px, cardY, pw, meC, True)

    If canClaimGone Then
        If UI_Button("og.claimwin", px, by1, bw, bh, "Claim win", True, _
                     "Your opponent left the game: win it.", BTN_PRIMARY) Then Online_ClaimAbandonment(True)
        If UI_Button("og.claimdraw", px + bw + gap, by1, bw, bh, "Call it a draw", True, _
                     "Your opponent left the game: end it as a draw.") Then Online_ClaimAbandonment(False)
    ElseIf active AndAlso Not connected Then
        '' The game cannot be played from here any more.
        If UI_Button("og.leave", px + bw + gap, by1, bw, bh, IIf(Online_Reconnecting(), "Stop trying", "Back to lobby"), _
                     True, "Leave this game screen. (The game goes on on the server: your opponent may claim it.)", _
                     BTN_PRIMARY) Then
            If Online_Reconnecting() Then Online_Disconnect()
            Online_ClearGame()
            OUI.gameId = ""
            nextScreen = SCREEN_ONLINE
        End If
    ElseIf active Then
        If g->drawOffer = oppC Then
            If UI_Button("og.accept", px, by1, bw, bh, "Accept draw", connected, "Agree to a draw.", BTN_PRIMARY) Then Online_AcceptDraw()
            If UI_Button("og.decline", px + bw + gap, by1, bw, bh, "Decline", connected, "Play on.") Then Online_DeclineDraw()
        Else
            If UI_Button("og.offer", px, by1, bw, bh, IIf(g->drawOffer = meC, "Draw offered", "Offer draw"), _
                         connected AndAlso g->drawOffer = "" AndAlso g->ply >= 2, "Ask your opponent for a draw.") Then
                Online_OfferDraw()
                OSetMessage("You offered a draw.", OUI_MSG_INFO)
            End If
            If g->ply < 2 Then
                If UI_Button("og.abort", px + bw + gap, by1, bw, bh, "Cancel game", connected, _
                             "Cancel before both players have moved (no result).") Then Online_Abort()
            ElseIf UI_Button("og.resign", px + bw + gap, by1, bw, bh, "Resign", connected, "Give up this game.", BTN_DANGER) Then
                Dialog_Open(OUI.dlg, "resign", "Resign?", "Do you really want to give up this game?", "Resign|Keep playing")
            End If
        End If
        If UI_Button("og.claim", px, by2, bw, bh, "Claim draw", connected AndAlso g->canClaim AndAlso myTurn, _
                     "Tournament rule: claim a draw after the same position three times or 50 moves without a capture or pawn move.") Then
            Online_ClaimDraw()
        End If
    Else
        If UI_Button("og.review", px, by1, bw, bh, "Review game", g->ply >= 2, _
                     "Look at every move with the computer's comments (now that the game is over).") Then
            If StartReview() Then nextScreen = SCREEN_REVIEW
        End If
        If UI_Button("og.lobby", px + bw + gap, by1, bw, bh, "Back to lobby", True, "Find the next game.", BTN_PRIMARY) Then
            Online_ClearGame()
            OUI.gameId = ""
            If Online_LoggedIn() AndAlso Not OUI.subscribed Then Online_LobbySubscribe() : OUI.subscribed = True
            nextScreen = SCREEN_ONLINE
        End If
        If UI_Button("og.save", px, by2, bw, bh, "Save PGN", g->pgn <> "", "Save this game as a PGN file.") Then SaveGamePgn()
    End If
    If UI_Button("og.flip", px + bw + gap, by2, bw, bh, "Flip board", True, "Turn the board around (F).") Then
        OUI.flipped = Not OUI.flipped
    End If
    If CBool(UI.keyCode = Asc("f") OrElse UI.keyCode = Asc("F")) AndAlso Not UI.blockInput Then OUI.flipped = Not OUI.flipped

    If OUI.dlg.active Then
        Dim As Integer r = Dialog_Run(OUI.dlg)
        If r = 0 AndAlso OUI.dlg.id = "resign" Then Online_Resign()
    End If
    Return nextScreen
End Function

'' ---------------------------------------------------------------------
'' Screenshot support: show the online screens with sample server data.
'' ---------------------------------------------------------------------
Sub Online_DebugSample(ByVal withGame As Boolean)
    Const Q = Chr(34)
    Online_DebugInject("{" & Q & "type" & Q & ":" & Q & "welcome" & Q & "," & Q & "features" & Q & ":{" & _
                       Q & "guests" & Q & ":true}}")
    Online_DebugInject("{" & Q & "type" & Q & ":" & Q & "logged_in" & Q & "," & Q & "player" & Q & ":{" & _
                       Q & "name" & Q & ":" & Q & "Guest_Maya" & Q & "}}")
    Dim As String players = ""
    Dim As String names(0 To 4) = {"Guest_Maya", "Guest_KnightRider", "Guest_Leo", "Guest_PawnStar", "Guest_Sophia"}
    Dim As String sts(0 To 4) = {"available", "available", "waiting", "playing", "playing"}
    Dim As Integer k
    For k = 0 To 4
        players &= IIf(k > 0, ",", "") & "{" & Q & "name" & Q & ":" & Q & names(k) & Q & "," & Q & "kind" & Q & ":" & _
                   Q & "guest" & Q & "," & Q & "status" & Q & ":" & Q & sts(k) & Q & "}"
    Next
    Online_DebugInject("{" & Q & "type" & Q & ":" & Q & "lobby" & Q & "," & Q & "total" & Q & ":5," & _
                       Q & "players" & Q & ":[" & players & "]}")
    If withGame Then
        Online_DebugInject("{" & Q & "type" & Q & ":" & Q & "game_started" & Q & "," & Q & "game" & Q & ":{" & _
            Q & "game_id" & Q & ":" & Q & "sample" & Q & "," & Q & "seq" & Q & ":6," & Q & "your_color" & Q & ":" & Q & "w" & Q & "," & _
            Q & "white" & Q & ":{" & Q & "name" & Q & ":" & Q & "Guest_Maya" & Q & "}," & _
            Q & "black" & Q & ":{" & Q & "name" & Q & ":" & Q & "Guest_KnightRider" & Q & "}," & _
            Q & "rated" & Q & ":false," & Q & "time_control" & Q & ":{" & Q & "initial_seconds" & Q & ":600," & Q & "increment_seconds" & Q & ":5}," & _
            Q & "moves" & Q & ":[" & Q & "e2e4" & Q & "," & Q & "e7e5" & Q & "," & Q & "g1f3" & Q & "," & Q & "b8c6" & Q & "," & Q & "f1c4" & Q & "," & Q & "f8c5" & Q & "]," & _
            Q & "san" & Q & ":[" & Q & "e4" & Q & "," & Q & "e5" & Q & "," & Q & "Nf3" & Q & "," & Q & "Nc6" & Q & "," & Q & "Bc4" & Q & "," & Q & "Bc5" & Q & "]," & _
            Q & "fen" & Q & ":" & Q & "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4" & Q & "," & _
            Q & "ply" & Q & ":6," & Q & "turn" & Q & ":" & Q & "w" & Q & "," & Q & "status" & Q & ":" & Q & "active" & Q & "," & _
            Q & "draw_offer" & Q & ":null," & Q & "clock" & Q & ":{" & Q & "white_ms" & Q & ":561000," & Q & "black_ms" & Q & ":587000," & _
            Q & "running" & Q & ":" & Q & "w" & Q & "}}}")
        OUI.gameId = ""
        SyncBoard()
    End If
End Sub

'' ---------------------------------------------------------------------
'' Online profile and match history
'' ---------------------------------------------------------------------
Private Function OutcomeText(ByRef o As Const String) As String
    Select Case o
    Case "win" : Return "won"
    Case "loss" : Return "lost"
    Case "draw" : Return "draw"
    Case Else : Return "cancelled"
    End Select
End Function

Private Function OutcomeColor(ByRef o As Const String) As ULong
    Select Case o
    Case "win" : Return RGB(30, 130, 50)
    Case "loss" : Return RGB(180, 60, 40)
    Case "draw" : Return RGB(60, 90, 160)
    Case Else : Return RGB(140, 130, 120)
    End Select
End Function

Function OnlineProfile_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_ONLINE_PROFILE
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    UI.blockInput = OUI.dlg.active OrElse OUI.credDlg.active OrElse OUI.chDlg.active
    UI_DrawBackground()
    Dim As Boolean own = (OUI.profileName = "")
    Screen_DrawHeader(IIf(own, "My online profile", "Player profile"))
    Dim As OnlineProfile Ptr pr = Online_Profile()
    Dim As ULong ink = RGB(50, 44, 36), soft = RGB(120, 105, 90)

    '' ---- Left: statistics
    Dim As Integer lx = 24, lw = 360, y = 62
    Gfx_Panel(lx, y, lw, sh - y - 84, 14, RGB(252, 249, 240), RGB(150, 120, 80))
    If Not pr->valid Then
        Text_Draw(lx + 16, y + 16, IIf(Online_Status() = OL_READY, "Loading...", "Not connected."), 20, soft)
    Else
        Text_Draw(lx + 16, y + 14, pr->playerName, 30, RGB(80, 52, 24))
        Text_Draw(lx + 16, y + 56, "Online rating: " & pr->rating & IIf(pr->provisional, " (provisional)", ""), 19, ink)
        Text_Draw(lx + 16, y + 84, "Member since " & pr->memberSince, 16, soft)
        Dim As Integer sy = y + 124, k
        Dim As String labels(0 To 4) = {"Games", "Won", "Drawn", "Lost", "Score"}
        Dim As String values(0 To 4)
        values(0) = Str(pr->games) : values(1) = Str(pr->wins) : values(2) = Str(pr->draws)
        values(3) = Str(pr->losses)
        values(4) = IIf(pr->games > 0, Int((pr->wins + pr->draws * 0.5) * 100 / pr->games + 0.5) & "%", "-")
        For k = 0 To 4
            Text_Draw(lx + 16, sy + k * 30, labels(k), 18, soft)
            Text_Draw(lx + 200, sy + k * 30, values(k), 18, ink)
        Next
        Text_DrawWrapped(lx + 16, sy + 170, lw - 32, _
            "The online rating is separate from your Beginner Chess player rating. It changes only in rated games.", _
            15, soft)
        If own Then
            If UI_Button("pf.delete", lx + 16, sh - 84 - 56, lw - 32, 40, "Delete my account", Online_Status() = OL_READY, _
                         "Removes your account. Your past games stay in your opponents' histories as 'Deleted player'.", _
                         BTN_DANGER) Then
                Dialog_Open(OUI.dlg, "delete", "Delete your account?", _
                            "This removes your account, rating and statistics for good. Your finished games stay in your " & _
                            "opponents' histories with the name 'Deleted player'. This cannot be undone.", _
                            "Delete account|Keep it")
            End If
        End If
    End If

    '' ---- Right: games
    Dim As Integer rx = lx + lw + 20, rw = sw - rx - 24, ry = 62, rh = sh - ry - 84
    Gfx_Panel(rx, ry, rw, rh, 14, RGB(255, 255, 255), RGB(150, 120, 80))
    Text_Draw(rx + 16, ry + 10, IIf(own, "Match history", "Recent games"), 20, RGB(80, 52, 24))
    Dim As Integer n = IIf(own, Online_HistoryCount(), pr->recentCount), k
    Dim As Integer rowH = 34, maxRows = (rh - 100) \ rowH
    For k = 0 To IIf(n < maxRows, n, maxRows) - 1
        Dim As OnlineGameSummary Ptr gsum = IIf(own, Online_HistoryEntry(k), @pr->recent(k))
        If gsum = 0 Then Exit For
        Dim As Integer yy = ry + 44 + k * rowH
        If (k Mod 2) = 0 Then Gfx_FillRect(rx + 8, yy - 4, rw - 16, rowH, RGB(246, 242, 232))
        Text_Draw(rx + 14, yy + 4, Mid(gsum->dateText, 6), 15, soft)
        Gfx_FillCircle(rx + 76, yy + 12, 6, IIf(gsum->colour = "w", RGB(250, 250, 245), RGB(40, 40, 45)))
        Gfx_Ring(rx + 76, yy + 12, 6, 1, RGB(120, 110, 100))
        Text_Draw(rx + 90, yy + 4, "vs " & Left(gsum->opponent, 18), 16, ink)
        Text_Draw(rx + rw - 300, yy + 4, OutcomeText(gsum->outcome), 16, OutcomeColor(gsum->outcome))
        Text_Draw(rx + rw - 210, yy + 4, gsum->minutes & "+" & gsum->increment & IIf(gsum->rated, " rated", ""), 15, soft)
        If UI_Button("pf.replay" & k, rx + rw - 104, yy - 1, 88, 28, "Replay", Online_Status() = OL_READY, _
                     "Replay this game move by move.") Then
            Online_RequestGameRecord(gsum->gameId)
        End If
    Next
    If n = 0 AndAlso pr->valid Then Text_Draw(rx + 16, ry + 48, "No games yet.", 18, soft)
    If own Then
        If UI_Button("pf.newer", rx + 16, ry + rh - 48, 140, 36, "< Newer", OUI.histOffset > 0, "More recent games.") Then
            OUI.histOffset = IIf(OUI.histOffset >= 20, OUI.histOffset - 20, 0)
            Online_RequestHistory(OUI.histOffset)
        End If
        If UI_Button("pf.older", rx + rw - 156, ry + rh - 48, 140, 36, "Older >", Online_HistoryCount() >= 20, "Older games.") Then
            OUI.histOffset += 20
            Online_RequestHistory(OUI.histOffset)
        End If
    End If

    If OUI.message <> "" AndAlso Timer - OUI.messageTime < 6 Then
        Text_Draw(180, sh - 52, Left(OUI.message, 90), 17, IIf(OUI.messageKind = OUI_MSG_BAD, RGB(255, 200, 190), RGB(220, 230, 245)))
    End If
    Dim As Boolean goBack = UI_Button("pf.back", 20, sh - 64, 140, 46, "< Back", True, "Back to Play Online.")
    If UI.keyCode = KEY_ESCAPE AndAlso Not UI.blockInput Then goBack = True
    If goBack Then nextScreen = SCREEN_ONLINE

    If OUI.dlg.active Then
        Dim As Integer r = Dialog_Run(OUI.dlg)
        If r = 0 AndAlso OUI.dlg.id = "delete" Then
            OpenCredDialog("delpass", "Delete account", "Type your password to delete the account " & Online_MyName() & ":", _
                           "", "Delete forever|Cancel", True)
        End If
    End If
    If OUI.credDlg.active Then RunCredDialog()
    Return nextScreen
End Function

Sub Online_DebugProfileSample()
    Const Q = Chr(34)
    Online_DebugInject("{" & Q & "type" & Q & ":" & Q & "logged_in" & Q & "," & Q & "player" & Q & ":{" & _
                       Q & "name" & Q & ":" & Q & "Maya_7" & Q & "," & Q & "kind" & Q & ":" & Q & "account" & Q & "," & _
                       Q & "rating" & Q & ":1234," & Q & "provisional" & Q & ":true}}")
    Dim As String games = "", opps(0 To 3) = {"Leo_K", "Guest_Sam", "Sophia", "Guest_Ann"}
    Dim As String outs(0 To 3) = {"win", "loss", "draw", "win"}
    Dim As Integer k
    For k = 0 To 3
        games &= IIf(k > 0, ",", "") & "{" & Q & "game_id" & Q & ":" & Q & "g" & k & Q & "," & Q & "opponent" & Q & ":" & _
                 Q & opps(k) & Q & "," & Q & "color" & Q & ":" & Q & IIf(k Mod 2 = 0, "w", "b") & Q & "," & _
                 Q & "outcome" & Q & ":" & Q & outs(k) & Q & "," & Q & "rated" & Q & ":false," & _
                 Q & "time_control" & Q & ":{" & Q & "initial_seconds" & Q & ":600," & Q & "increment_seconds" & Q & ":0}," & _
                 Q & "date" & Q & ":" & Q & "2026-10-0" & (8 - k) & Q & "}"
    Next
    Online_DebugInject("{" & Q & "type" & Q & ":" & Q & "profile" & Q & "," & Q & "profile" & Q & ":{" & _
                       Q & "name" & Q & ":" & Q & "Maya_7" & Q & "," & Q & "rating" & Q & ":1234," & _
                       Q & "provisional" & Q & ":true," & Q & "games" & Q & ":4," & Q & "wins" & Q & ":2," & _
                       Q & "losses" & Q & ":1," & Q & "draws" & Q & ":1," & Q & "member_since" & Q & ":" & Q & "2026-10" & Q & "," & _
                       Q & "recent_games" & Q & ":[" & games & "]}}")
    Online_DebugInject("{" & Q & "type" & Q & ":" & Q & "history" & Q & "," & Q & "offset" & Q & ":0," & _
                       Q & "games" & Q & ":[" & games & "]}")
    OUI.profileName = ""
    OUI.histOffset = 0
End Sub

'' ---------------------------------------------------------------------
'' Leaderboard
'' ---------------------------------------------------------------------
Function OnlineLeaderboard_Frame() As Integer
    Dim As Integer nextScreen = SCREEN_ONLINE_LEADERBOARD
    Dim As Integer sw = Gfx_Width(), sh = Gfx_Height()
    UI.blockInput = OUI.chDlg.active
    UI_DrawBackground()
    Screen_DrawHeader("Leaderboard")
    Dim As ULong ink = RGB(50, 44, 36), soft = RGB(120, 105, 90)
    Dim As Integer px = 60, pw = sw - 120, py = 62, ph = sh - py - 84
    Gfx_Panel(px, py, pw, ph, 14, RGB(255, 255, 255), RGB(150, 120, 80))
    Text_Draw(px + 20, py + 12, "Rank", 18, RGB(80, 52, 24))
    Text_Draw(px + 110, py + 12, "Player", 18, RGB(80, 52, 24))
    Text_Draw(px + pw - 320, py + 12, "Rating", 18, RGB(80, 52, 24))
    Text_Draw(px + pw - 170, py + 12, "Rated games", 18, RGB(80, 52, 24))
    Dim As Integer k, rowH = 28
    For k = 0 To Online_LeaderCount() - 1
        Dim As OnlineLeaderEntry Ptr e = Online_LeaderEntry(k)
        Dim As Integer yy = py + 48 + k * rowH
        If yy + rowH > py + ph - 56 Then Exit For
        If (k Mod 2) = 0 Then Gfx_FillRect(px + 8, yy - 3, pw - 16, rowH, RGB(246, 242, 232))
        Dim As Boolean isMe = (e->playerName = Online_MyName())
        If UI_Hover(px + 8, yy - 3, pw - 16, rowH) Then
            Gfx_FillRect(px + 8, yy - 3, pw - 16, rowH, RGBA(52, 120, 206, 40))
            UI_SetTooltip("lb.row" & k, "Show " & e->playerName & "'s profile.")
            If UI.released Then
                Online_ShowProfile(e->playerName)
                nextScreen = SCREEN_ONLINE_PROFILE
            End If
        End If
        Dim As ULong c = IIf(isMe, RGB(30, 110, 50), ink)
        Text_Draw(px + 20, yy + 2, Str(e->rank), 17, c)
        DrawListName(px + 110, yy + 2, pw - 445, e->playerName, isMe, c)
        Text_Draw(px + pw - 320, yy + 2, e->rating & IIf(e->provisional, "?", ""), 17, c)
        Text_Draw(px + pw - 170, yy + 2, Str(e->games), 17, soft)
    Next
    If Online_LeaderCount() = 0 Then
        Text_DrawWrapped(px + 20, py + 56, pw - 40, IIf(Online_Status() = OL_READY, _
            "Nobody has played a rated game yet. Be the first!", "Not connected."), 18, soft)
    End If
    Text_Draw(px + 20, py + ph - 40, "A question mark means provisional: fewer than 20 rated games.", 15, soft)
    Dim As Integer off = Online_LeaderOffset()
    If UI_Button("lb.prev", px + pw - 300, py + ph - 48, 130, 36, "< Higher", off > 0, "Better ranks.") Then
        Online_RequestLeaderboard(IIf(off >= 20, off - 20, 0))
    End If
    If UI_Button("lb.next", px + pw - 160, py + ph - 48, 130, 36, "Lower >", off + Online_LeaderCount() < Online_LeaderTotal(), _
                 "Further ranks.") Then
        Online_RequestLeaderboard(off + 20)
    End If
    Dim As Boolean goBack = UI_Button("lb.back", 20, sh - 64, 140, 46, "< Back", True, "Back to Play Online.")
    If UI.keyCode = KEY_ESCAPE AndAlso Not UI.blockInput Then goBack = True
    If goBack Then nextScreen = SCREEN_ONLINE
    Return nextScreen
End Function
