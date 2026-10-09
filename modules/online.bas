'' =====================================================================
'' BeginnerChess - online.bas
'' Multiplayer protocol client. See online.bi.
'' =====================================================================
#include once "online.bi"
#include once "chessdefs.bi"

Const HEARTBEAT_SECONDS = 15        '' ping when nothing was received for this long
Const SILENCE_LIMIT = 45            '' no message at all for this long: connection lost
Const REQUEST_TIMEOUT = 15          '' an answer should arrive within this time
Const MAX_PENDING = 64
Const MAX_EVENTS = 256

Declare Sub ForgetLogin()

Type PendingRequest
    id    As String
    rtype As String
    sent  As Double
End Type

Dim Shared OLStatus As Integer = OL_OFFLINE
Dim Shared OLStatusText As String
Dim Shared OLHost As String
Dim Shared OLUrl As String
Dim Shared OLFeatures As String           '' "|guests|registration|" (features switched on)
Dim Shared OLNextId As Integer
Dim Shared OLLastReceive As Double
Dim Shared OLLastPing As Double
Dim Shared OLPending(0 To MAX_PENDING - 1) As PendingRequest
Dim Shared OLPendingCount As Integer
Dim Shared OLEvents(0 To MAX_EVENTS - 1) As OnlineEvent
Dim Shared OLEventHead As Integer, OLEventCount As Integer
Dim Shared OLGame As OnlineGame
Dim Shared OLMyName As String
Dim Shared OLMyKind As String
Dim Shared OLMyRating As Integer = -1
Dim Shared OLMyProvisional As Boolean
Dim Shared OLToken As String
Dim Shared OLProfile As OnlineProfile
Dim Shared OLHistory(Any) As OnlineGameSummary
Dim Shared OLHistoryCount As Integer, OLHistoryOffset As Integer
Dim Shared OLIncoming(0 To 15) As OnlineChallenge
Dim Shared OLIncomingCount As Integer
Dim Shared OLOutgoing As OnlineChallenge
Dim Shared OLAcceptingId As String         '' challenge whose acceptance is on its way
Dim Shared OLLeaders(Any) As OnlineLeaderEntry
Dim Shared OLLeaderCount As Integer, OLLeaderTotal As Integer, OLLeaderOffset As Integer
'' Automatic reconnection after a connection loss during a game.
Dim Shared OLReconnecting As Boolean
Dim Shared OLReconnectToken As String
Dim Shared OLReconnectAt As Double
Dim Shared OLReconnectStart As Double
Dim Shared OLReconnectTries As Integer
Const RECONNECT_GIVE_UP = 90           '' seconds
Dim Shared OLWaiting As Boolean
Dim Shared OLLobby(Any) As OnlineLobbyEntry
Dim Shared OLLobbyCount As Integer, OLLobbyTotal As Integer

'' ---------------------------------------------------------------------
'' Events and requests
'' ---------------------------------------------------------------------
Private Sub PushEvent(ByRef kind As Const String, ByRef text As Const String = "", _
                      ByRef rid As Const String = "", ByRef rtype As Const String = "", _
                      ByRef code As Const String = "", ByRef message As Const String = "")
    If OLEventCount >= MAX_EVENTS Then                  '' drop the oldest
        OLEventHead = (OLEventHead + 1) Mod MAX_EVENTS
        OLEventCount -= 1
    End If
    Dim As Integer i = (OLEventHead + OLEventCount) Mod MAX_EVENTS
    With OLEvents(i)
        .kind = kind : .text = text : .requestId = rid : .requestType = rtype
        .code = code : .message = message
    End With
    OLEventCount += 1
End Sub

Function Online_NextEvent(ByRef ev As OnlineEvent) As Boolean
    If OLEventCount = 0 Then Return False
    ev = OLEvents(OLEventHead)
    OLEvents(OLEventHead).text = ""
    OLEventHead = (OLEventHead + 1) Mod MAX_EVENTS
    OLEventCount -= 1
    Return True
End Function

Private Sub AddPending(ByRef id As Const String, ByRef rtype As Const String)
    If OLPendingCount >= MAX_PENDING Then              '' forget the oldest
        Dim As Integer k
        For k = 1 To MAX_PENDING - 1
            OLPending(k - 1) = OLPending(k)
        Next
        OLPendingCount -= 1
    End If
    OLPending(OLPendingCount).id = id
    OLPending(OLPendingCount).rtype = rtype
    OLPending(OLPendingCount).sent = Timer
    OLPendingCount += 1
End Sub

'' Removes request id from the pending list; returns its type ("" if unknown).
Private Function TakePending(ByRef id As Const String) As String
    Dim As Integer k, j
    For k = 0 To OLPendingCount - 1
        If OLPending(k).id = id Then
            Dim As String t = OLPending(k).rtype
            For j = k + 1 To OLPendingCount - 1
                OLPending(j - 1) = OLPending(j)
            Next
            OLPendingCount -= 1
            Return t
        End If
    Next
    Return ""
End Function

Function Online_PendingCount() As Integer
    Return OLPendingCount
End Function

'' Sends a request built in w (JW_Begin and "type" already written by the caller).
Private Function SendRequest(ByRef w As JsonWriter, ByRef rtype As Const String) As String
    If OLStatus <> OL_READY AndAlso rtype <> "hello" Then Return ""
    OLNextId += 1
    Dim As String id = "c" & OLNextId
    JW_Str(w, "request_id", id)
    If Not Net_Send(JW_Text(w)) Then Return ""
    AddPending(id, rtype)
    Return id
End Function

Private Sub StartRequest(ByRef w As JsonWriter, ByRef rtype As Const String)
    JW_Begin(w)
    JW_Str(w, "type", rtype)
End Sub

'' ---------------------------------------------------------------------
'' Connection
'' ---------------------------------------------------------------------
Function Online_Connect(ByRef url As Const String, ByRef errMsg As String) As Boolean
    Online_Disconnect()
    Dim As Boolean secure
    Dim As String path
    Dim As Integer port
    If Not Net_ParseUrl(url, secure, OLHost, port, path, errMsg) Then Return False
    If Not Net_Connect(url, errMsg) Then
        OLStatus = OL_LOST
        OLStatusText = errMsg
        Return False
    End If
    ForgetLogin()
    OLUrl = url
    OLStatus = OL_CONNECTING
    OLStatusText = "Connecting to " & OLHost & "..."
    OLFeatures = ""
    OLPendingCount = 0
    OLLastReceive = Timer
    OLLastPing = Timer
    Return True
End Function

Sub Online_Disconnect()
    ForgetLogin()
    OLReconnecting = False
    OLReconnectToken = ""
    If OLStatus = OL_RECONNECTING Then OLStatus = OL_OFFLINE
    If OLStatus = OL_OFFLINE AndAlso Net_State() = NET_IDLE Then Exit Sub
    Net_Disconnect()
    OLStatus = OL_OFFLINE
    OLStatusText = "Not connected"
    OLPendingCount = 0
End Sub

Function Online_Status() As Integer
    Return OLStatus
End Function

Function Online_StatusText() As String
    If OLStatusText = "" Then Return "Not connected"
    Return OLStatusText
End Function

Function Online_ServerHost() As String
    Return OLHost
End Function

Function Online_Feature(ByRef featureName As Const String) As Boolean
    Return InStr(OLFeatures, "|" & featureName & "|") > 0
End Function

Private Function CloseCodeText(ByVal code As Integer) As String
    Select Case code
    Case 4001 : Return "Your BeginnerChess version is incompatible with this multiplayer server. Please update BeginnerChess."
    Case 4008 : Return "The server closed the connection because of invalid requests."
    Case 4009 : Return "You logged in from another place."
    Case 4010 : Return "The server operator ended this session."
    Case 1001 : Return "The server is restarting. Please connect again in a moment."
    Case 1013 : Return "The server is busy. Please try again later."
    Case Else : Return "The connection was closed."
    End Select
End Function

Private Sub ConnectionEnded(ByRef why As Const String, ByVal lost As Boolean)
    If OLStatus = OL_OFFLINE OrElse OLStatus = OL_LOST OrElse OLStatus = OL_RECONNECTING Then Exit Sub
    '' Lost during a running game: come back automatically (the game waits).
    Dim As String tok = IIf(OLReconnecting, OLReconnectToken, OLToken)
    If lost AndAlso CBool(tok <> "") AndAlso OLGame.active AndAlso CBool(OLGame.status = "active") Then
        If Not OLReconnecting Then
            OLReconnecting = True
            OLReconnectStart = Timer
            OLReconnectTries = 0
        End If
        OLReconnectToken = tok
        If Timer - OLReconnectStart < RECONNECT_GIVE_UP Then
            OLReconnectTries += 1
            Dim As Double pause = IIf(OLReconnectTries > 4, 8, 2 ^ (OLReconnectTries - 1))
            OLReconnectAt = Timer + pause
            OLStatus = OL_RECONNECTING
            OLStatusText = "Connection lost - reconnecting..."
            OLPendingCount = 0
            PushEvent("reconnecting", "", "", "", "", why)
            Exit Sub
        End If
        OLReconnecting = False
        OLReconnectToken = ""
    End If
    OLStatus = IIf(lost, OL_LOST, OL_OFFLINE)
    OLStatusText = why
    OLPendingCount = 0
    ForgetLogin()
    PushEvent(IIf(lost, "connection_lost", "connection_closed"), "", "", "", "", why)
End Sub

'' ---------------------------------------------------------------------
'' Game model updates
'' ---------------------------------------------------------------------
Private Sub ReadClock(ByRef d As JsonDoc, ByVal node As Long)
    Dim As Long c = Json_Member(d, node, "clock")
    If c < 0 Then Exit Sub
    OLGame.whiteMs = Json_GetInt(d, c, "white_ms", OLGame.whiteMs)
    OLGame.blackMs = Json_GetInt(d, c, "black_ms", OLGame.blackMs)
    OLGame.running = Json_GetStr(d, c, "running", "")
    OLGame.firstMoveMs = IIf(Json_IsNull(d, c, "first_move_ms"), -1, Json_GetInt(d, c, "first_move_ms", -1))
    OLGame.clockAt = Timer
End Sub

Private Sub ReadPlayer(ByRef d As JsonDoc, ByVal node As Long, ByRef nm As String, ByRef rating As Integer)
    nm = Json_GetStr(d, node, "name", "?")
    rating = IIf(Json_Has(d, node, "rating"), CInt(Json_GetInt(d, node, "rating", -1)), -1)
End Sub

'' Full snapshot (game_started, game_state).
Private Sub ReadSnapshot(ByRef d As JsonDoc, ByVal g As Long)
    With OLGame
        .active = True
        .gameId = Json_GetStr(d, g, "game_id")
        .seq = Json_GetInt(d, g, "seq")
        .myColor = Json_GetStr(d, g, "your_color", .myColor)
        ReadPlayer(d, Json_Member(d, g, "white"), .whiteName, .whiteRating)
        ReadPlayer(d, Json_Member(d, g, "black"), .blackName, .blackRating)
        .rated = Json_GetBool(d, g, "rated")
        Dim As Long tc = Json_Member(d, g, "time_control")
        .initialSec = Json_GetInt(d, tc, "initial_seconds")
        .incrementSec = Json_GetInt(d, tc, "increment_seconds")
        Dim As Long mv = Json_Member(d, g, "moves"), sn = Json_Member(d, g, "san")
        Dim As Integer n = Json_Count(d, mv), k
        If n > 0 Then
            ReDim .moves(0 To n - 1)
            ReDim .sans(0 To n - 1)
            For k = 0 To n - 1
                .moves(k) = Json_Str(d, Json_Item(d, mv, k))
                .sans(k) = Json_Str(d, Json_Item(d, sn, k))
            Next
        Else
            Erase .moves
            Erase .sans
        End If
        .ply = Json_GetInt(d, g, "ply", n)
        .fen = Json_GetStr(d, g, "fen")
        .turn = Json_GetStr(d, g, "turn", "w")
        .inCheck = Json_GetBool(d, g, "in_check")
        .status = Json_GetStr(d, g, "status", "active")
        .result = Json_GetStr(d, g, "result")
        .termination = Json_GetStr(d, g, "termination")
        .drawOffer = Json_GetStr(d, g, "draw_offer")
        .canClaim = Json_GetBool(d, g, "can_claim_draw")
        .pgn = ""
        .needResync = False
        Dim As Long aw = Json_Member(d, g, "away")
        Dim As String oppC = IIf(.myColor = "w", "b", "w")
        .opponentAway = Json_Has(d, aw, oppC)
        If .opponentAway Then .awaySince = Timer - Json_GetInt(d, aw, oppC)
        If .graceSec = 0 Then .graceSec = 60
    End With
    ReadClock(d, g)
End Sub

Sub ForgetLogin()
    OLMyName = "" : OLMyKind = "" : OLMyRating = -1 : OLToken = ""
    OLWaiting = False : OLLobbyCount = 0 : OLLobbyTotal = 0 : OLHistoryCount = 0
    Dim As OnlineProfile empty
    OLProfile = empty
    OLIncomingCount = 0
    OLOutgoing.challengeId = ""
End Sub

Private Sub RemoveChallenge(ByRef cid As Const String)
    If OLOutgoing.challengeId = cid Then OLOutgoing.challengeId = ""
    Dim As Integer k, j
    For k = 0 To OLIncomingCount - 1
        If OLIncoming(k).challengeId = cid Then
            For j = k + 1 To OLIncomingCount - 1
                OLIncoming(j - 1) = OLIncoming(j)
            Next
            OLIncomingCount -= 1
            Exit For
        End If
    Next
End Sub

Private Sub ReadChallenge(ByRef d As JsonDoc, ByVal node As Long, ByRef side As Const String, ByRef c As OnlineChallenge)
    Dim As Long who = Json_Member(d, node, side)
    c.challengeId = Json_GetStr(d, node, "challenge_id")
    c.playerName = Json_GetStr(d, who, "name", "?")
    c.rating = IIf(Json_Has(d, who, "rating"), CInt(Json_GetInt(d, who, "rating", -1)), -1)
    Dim As Long tc = Json_Member(d, node, "time_control")
    c.minutes = Json_GetInt(d, tc, "initial_seconds") \ 60
    c.increment = Json_GetInt(d, tc, "increment_seconds")
    c.rated = Json_GetBool(d, node, "rated")
    c.received = Timer
End Sub

Private Sub ReadSummary(ByRef d As JsonDoc, ByVal node As Long, ByRef s As OnlineGameSummary)
    s.gameId = Json_GetStr(d, node, "game_id")
    s.whiteName = Json_GetStr(d, node, "white")
    s.blackName = Json_GetStr(d, node, "black")
    s.opponent = Json_GetStr(d, node, "opponent")
    s.colour = Json_GetStr(d, node, "color")
    s.outcome = Json_GetStr(d, node, "outcome")
    s.result = Json_GetStr(d, node, "result")
    s.termination = Json_GetStr(d, node, "termination")
    s.rated = Json_GetBool(d, node, "rated")
    Dim As Long tc = Json_Member(d, node, "time_control")
    s.minutes = Json_GetInt(d, tc, "initial_seconds") \ 60
    s.increment = Json_GetInt(d, tc, "increment_seconds")
    s.dateText = Json_GetStr(d, node, "date")
End Sub

Private Sub RequestResync()
    If OLGame.needResync Then Exit Sub
    OLGame.needResync = True
    Online_RequestGameState()
End Sub

'' move_accepted: append the move if it is the next one, else resynchronise.
Private Sub ReadMove(ByRef d As JsonDoc)
    If Json_GetStr(d, 0, "game_id") <> OLGame.gameId Then Exit Sub
    Dim As Integer ply = Json_GetInt(d, 0, "ply")
    If ply = OLGame.ply Then Exit Sub                         '' a repeated answer (retry)
    If ply <> OLGame.ply + 1 Then
        RequestResync()
        Exit Sub
    End If
    With OLGame
        ReDim Preserve .moves(0 To ply - 1)
        ReDim Preserve .sans(0 To ply - 1)
        .moves(ply - 1) = Json_GetStr(d, 0, "move")
        .sans(ply - 1) = Json_GetStr(d, 0, "san")
        .ply = ply
        .seq = Json_GetInt(d, 0, "seq", .seq)
        .fen = Json_GetStr(d, 0, "fen")
        .turn = Json_GetStr(d, 0, "turn", .turn)
        .inCheck = Json_GetBool(d, 0, "in_check")
        .drawOffer = Json_GetStr(d, 0, "draw_offer")
        .canClaim = Json_GetBool(d, 0, "can_claim_draw")
    End With
    ReadClock(d, 0)
End Sub

Private Sub ReadGameOver(ByRef d As JsonDoc)
    If Json_GetStr(d, 0, "game_id") <> OLGame.gameId Then Exit Sub
    With OLGame
        .seq = Json_GetInt(d, 0, "seq", .seq)
        .status = Json_GetStr(d, 0, "status", "finished")
        .result = Json_GetStr(d, 0, "result")
        .termination = Json_GetStr(d, 0, "termination")
        .drawOffer = ""
        .canClaim = False
        .pgn = Json_GetStr(d, 0, "pgn")
    End With
    ReadClock(d, 0)
End Sub

'' ---------------------------------------------------------------------
'' Main loop
'' ---------------------------------------------------------------------
Private Sub HandleMessage(ByRef text As Const String)
    Dim As JsonDoc d
    Dim As String perr
    If Not Json_Parse(d, text, perr) OrElse Json_Kind(d, 0) <> JK_OBJECT Then
        PushEvent("protocol_error", text, "", "", "", "The server sent something unreadable.")
        Exit Sub
    End If
    Dim As String mtype = Json_GetStr(d, 0, "type")
    Dim As String rid = Json_GetStr(d, 0, "request_id")
    Dim As String rtype = IIf(rid <> "", TakePending(rid), "")
    Select Case mtype
    Case "welcome"
        OLStatus = OL_READY
        OLStatusText = "Connected to " & OLHost
        If OLReconnecting Then Online_Resume(OLReconnectToken)
        Dim As Long f = Json_Member(d, 0, "features")
        OLFeatures = "|"
        Dim As Integer k
        For k = 0 To Json_Count(d, f) - 1
            Dim As Long item = Json_Item(d, f, k)
            If Json_Kind(d, item) = JK_BOOL AndAlso d.nodes(item).bval Then OLFeatures &= d.nodes(item).key & "|"
        Next
    Case "logged_in"
        Dim As Long pl = Json_Member(d, 0, "player")
        OLMyName = Json_GetStr(d, pl, "name", "?")
        OLMyKind = Json_GetStr(d, pl, "kind", "guest")
        OLMyRating = IIf(Json_Has(d, pl, "rating"), CInt(Json_GetInt(d, pl, "rating", -1)), -1)
        OLMyProvisional = Json_GetBool(d, pl, "provisional")
        OLToken = Json_GetStr(d, 0, "session_token")
        If OLReconnecting Then
            OLReconnecting = False
            OLReconnectToken = ""
        End If
    Case "logged_out", "account_deleted", "session_replaced"
        ForgetLogin()
    Case "profile"
        Dim As Long pr = Json_Member(d, 0, "profile")
        With OLProfile
            .valid = True
            .playerName = Json_GetStr(d, pr, "name")
            .rating = Json_GetInt(d, pr, "rating", 1200)
            .provisional = Json_GetBool(d, pr, "provisional")
            .ratedGames = Json_GetInt(d, pr, "rated_games")
            .games = Json_GetInt(d, pr, "games")
            .wins = Json_GetInt(d, pr, "wins")
            .losses = Json_GetInt(d, pr, "losses")
            .draws = Json_GetInt(d, pr, "draws")
            .memberSince = Json_GetStr(d, pr, "member_since")
            Dim As Long rg = Json_Member(d, pr, "recent_games")
            .recentCount = Json_Count(d, rg)
            If .recentCount > 0 Then ReDim .recent(0 To .recentCount - 1)
            Dim As Integer i
            For i = 0 To .recentCount - 1
                ReadSummary(d, Json_Item(d, rg, i), .recent(i))
            Next
        End With
    Case "history"
        Dim As Long hg = Json_Member(d, 0, "games")
        OLHistoryCount = Json_Count(d, hg)
        OLHistoryOffset = Json_GetInt(d, 0, "offset")
        If OLHistoryCount > 0 Then ReDim OLHistory(0 To OLHistoryCount - 1)
        Dim As Integer i
        For i = 0 To OLHistoryCount - 1
            ReadSummary(d, Json_Item(d, hg, i), OLHistory(i))
        Next
    Case "matchmaking_waiting"
        OLWaiting = True
    Case "matchmaking_found"
        OLWaiting = False
    Case "lobby"
        Dim As Long pl = Json_Member(d, 0, "players")
        OLLobbyCount = Json_Count(d, pl)
        OLLobbyTotal = Json_GetInt(d, 0, "total", OLLobbyCount)
        If OLLobbyCount > 0 Then ReDim OLLobby(0 To OLLobbyCount - 1)
        Dim As Integer k
        For k = 0 To OLLobbyCount - 1
            Dim As Long e = Json_Item(d, pl, k)
            OLLobby(k).playerName = Json_GetStr(d, e, "name", "?")
            OLLobby(k).kind = Json_GetStr(d, e, "kind")
            OLLobby(k).rating = IIf(Json_Has(d, e, "rating"), CInt(Json_GetInt(d, e, "rating", -1)), -1)
            OLLobby(k).status = Json_GetStr(d, e, "status")
        Next
    Case "game_started"
        OLWaiting = False
        OLIncomingCount = 0
        OLOutgoing.challengeId = ""
        ReadSnapshot(d, Json_Member(d, 0, "game"))
        OLGame.myBefore = -1
    Case "game_resumed"
        Dim As Long rg = Json_Member(d, 0, "game")
        Dim As Boolean sameGame = (Json_GetStr(d, rg, "game_id") = OLGame.gameId)
        ReadSnapshot(d, rg)
        If Not sameGame Then OLGame.myBefore = -1
    Case "opponent_disconnected"
        If Json_GetStr(d, 0, "game_id") = OLGame.gameId Then
            OLGame.opponentAway = True
            OLGame.awaySince = Timer
            OLGame.graceSec = Json_GetInt(d, 0, "grace_seconds", 60)
        End If
    Case "opponent_reconnected"
        If Json_GetStr(d, 0, "game_id") = OLGame.gameId Then OLGame.opponentAway = False
    Case "rating_update"
        If Json_GetStr(d, 0, "game_id") = OLGame.gameId Then
            Dim As Long mine = Json_Member(d, 0, IIf(OLGame.myColor = "w", "white", "black"))
            OLGame.myBefore = Json_GetInt(d, mine, "before", -1)
            OLGame.myAfter = Json_GetInt(d, mine, "after", -1)
            OLMyRating = OLGame.myAfter
            OLMyProvisional = Json_GetBool(d, mine, "provisional")
        End If
    Case "challenge_sent"
        ReadChallenge(d, Json_Member(d, 0, "challenge"), "to", OLOutgoing)
    Case "challenge_received"
        If OLIncomingCount <= UBound(OLIncoming) Then
            ReadChallenge(d, Json_Member(d, 0, "challenge"), "from", OLIncoming(OLIncomingCount))
            OLIncomingCount += 1
        End If
    Case "challenge_accepted", "challenge_declined", "challenge_cancelled", "challenge_expired"
        RemoveChallenge(Json_GetStr(d, 0, "challenge_id"))
    Case "leaderboard"
        Dim As Long lp = Json_Member(d, 0, "players")
        OLLeaderCount = Json_Count(d, lp)
        OLLeaderTotal = Json_GetInt(d, 0, "total")
        OLLeaderOffset = Json_GetInt(d, 0, "offset")
        If OLLeaderCount > 0 Then ReDim OLLeaders(0 To OLLeaderCount - 1)
        Dim As Integer li
        For li = 0 To OLLeaderCount - 1
            Dim As Long e = Json_Item(d, lp, li)
            OLLeaders(li).rank = Json_GetInt(d, e, "rank")
            OLLeaders(li).playerName = Json_GetStr(d, e, "name")
            OLLeaders(li).rating = Json_GetInt(d, e, "rating")
            OLLeaders(li).games = Json_GetInt(d, e, "games")
            OLLeaders(li).provisional = Json_GetBool(d, e, "provisional")
        Next
    Case "game_state"
        Dim As Long g = Json_Member(d, 0, "game")
        If Json_GetStr(d, g, "game_id") = OLGame.gameId OrElse Not OLGame.active Then ReadSnapshot(d, g)
    Case "move_accepted"
        ReadMove(d)
    Case "game_over"
        ReadGameOver(d)
    Case "draw_offered"
        If Json_GetStr(d, 0, "game_id") = OLGame.gameId Then
            OLGame.drawOffer = IIf(OLGame.myColor = "w", "b", "w")
            OLGame.seq = Json_GetInt(d, 0, "seq", OLGame.seq)
        End If
    Case "draw_declined"
        If Json_GetStr(d, 0, "game_id") = OLGame.gameId Then
            OLGame.drawOffer = ""
            OLGame.seq = Json_GetInt(d, 0, "seq", OLGame.seq)
        End If
    Case "ok"
        If rtype = "matchmaking_cancel" Then OLWaiting = False
        If rtype = "challenge_cancel" OrElse rtype = "challenge_decline" OrElse rtype = "challenge_accept" Then
            RemoveChallenge(Json_GetStr(d, 0, "challenge_id"))
        End If
        If rtype = "offer_draw" Then OLGame.drawOffer = OLGame.myColor
        If rtype = "decline_draw" Then OLGame.drawOffer = ""
    Case "error"
        Dim As String code = Json_GetStr(d, 0, "code")
        '' A move that did not fit the server's state: reload the game.
        If rtype = "move" AndAlso (code = "conflict" OrElse code = "not_your_turn" OrElse code = "illegal_move") Then
            RequestResync()
        End If
        If code = "game_over" AndAlso OLGame.active Then RequestResync()
        If rtype = "resume" AndAlso OLReconnecting Then
            OLReconnecting = False
            OLReconnectToken = ""
        End If
        If rtype = "challenge_accept" Then RemoveChallenge(OLAcceptingId)       '' expired or taken back
        If code = "incompatible_version" Then
            OLStatusText = Json_GetStr(d, 0, "message")
        End If
        PushEvent("error", text, rid, rtype, code, Json_GetStr(d, 0, "message"))
        Exit Sub
    Case "server_shutdown"
        PushEvent(mtype, text, rid, rtype, "", Json_GetStr(d, 0, "message"))
        Exit Sub
    End Select
    PushEvent(mtype, text, rid, rtype)
End Sub

Sub Online_Update(ByVal now As Double)
    If OLStatus = OL_RECONNECTING Then
        If now >= OLReconnectAt Then
            Dim As String e
            If Net_Connect(OLUrl, e) Then
                OLStatus = OL_CONNECTING
                OLStatusText = "Reconnecting to " & OLHost & "..."
                OLLastReceive = now
            Else
                OLReconnectAt = now + 8
            End If
        End If
        Exit Sub
    End If
    If OLStatus = OL_OFFLINE OrElse OLStatus = OL_LOST Then Exit Sub
    Dim As Integer ns = Net_State()
    If OLStatus = OL_CONNECTING AndAlso ns = NET_OPEN Then
        '' Connected: introduce ourselves.
        OLStatus = OL_HANDSHAKE
        OLStatusText = "Talking to " & OLHost & "..."
        Dim As JsonWriter w
        StartRequest(w, "hello")
        JW_Int(w, "protocol_version", ONLINE_PROTOCOL_VERSION)
        JW_Str(w, "client_name", "BeginnerChess")
        JW_Str(w, "client_version", CM_VERSION)
        SendRequest(w, "hello")
        OLLastReceive = now
    End If
    '' Take everything that has arrived (also after the connection closed).
    Dim As String text
    Dim As Integer handled = 0
    Do While handled < 200 AndAlso Net_Receive(text)
        OLLastReceive = now
        HandleMessage(text)
        handled += 1
    Loop
    ns = Net_State()
    If ns = NET_FAILED Then
        ConnectionEnded(Net_Error(), True)
        Exit Sub
    ElseIf ns = NET_CLOSED Then
        ConnectionEnded(CloseCodeText(Net_CloseCode()), Net_CloseCode() <> 1000)
        Exit Sub
    End If
    If OLStatus = OL_READY Then
        '' Heartbeat: the server answers pings, so silence means trouble.
        If now - OLLastReceive > HEARTBEAT_SECONDS AndAlso now - OLLastPing > HEARTBEAT_SECONDS Then
            OLLastPing = now
            Online_Ping()
        End If
        If now - OLLastReceive > SILENCE_LIMIT Then
            Net_Disconnect()
            ConnectionEnded("The server stopped answering.", True)
            Exit Sub
        End If
    ElseIf OLStatus = OL_HANDSHAKE AndAlso now - OLLastReceive > REQUEST_TIMEOUT Then
        Net_Disconnect()
        ConnectionEnded("The server did not answer.", True)
        Exit Sub
    End If
    '' Requests without an answer.
    Dim As Integer k = 0
    Do While k < OLPendingCount
        If now - OLPending(k).sent > REQUEST_TIMEOUT Then
            Dim As String id = OLPending(k).id, rt = OLPending(k).rtype
            TakePending(id)
            PushEvent("request_timeout", "", id, rt, "", "The server did not answer in time.")
        Else
            k += 1
        End If
    Loop
End Sub

'' ---------------------------------------------------------------------
'' Requests
'' ---------------------------------------------------------------------
Function Online_LoginGuest(ByRef nickname As Const String) As String
    Dim As JsonWriter w
    StartRequest(w, "login_guest")
    JW_Str(w, "nickname", nickname)
    Return SendRequest(w, "login_guest")
End Function

Function Online_QuickMatch(ByVal minutes As Integer, ByVal incrementSec As Integer, ByVal rated As Boolean) As String
    Dim As JsonWriter w
    StartRequest(w, "matchmaking_join")
    JW_BeginObj(w, "time_control")
    JW_Int(w, "initial_seconds", minutes * 60)
    JW_Int(w, "increment_seconds", incrementSec)
    JW_End(w)
    JW_Bool(w, "rated", rated)
    Return SendRequest(w, "matchmaking_join")
End Function

Function Online_CancelMatch() As String
    Dim As JsonWriter w
    StartRequest(w, "matchmaking_cancel")
    Return SendRequest(w, "matchmaking_cancel")
End Function

Private Function GameRequest(ByRef rtype As Const String) As String
    If OLGame.gameId = "" Then Return ""
    Dim As JsonWriter w
    StartRequest(w, rtype)
    JW_Str(w, "game_id", OLGame.gameId)
    Return SendRequest(w, rtype)
End Function

Function Online_SendMove(ByRef uci As Const String, ByVal claimDraw As Boolean = False) As String
    If OLGame.gameId = "" Then Return ""
    Dim As JsonWriter w
    StartRequest(w, "move")
    JW_Str(w, "game_id", OLGame.gameId)
    JW_Str(w, "move", uci)
    JW_Int(w, "expected_ply", OLGame.ply)
    If claimDraw Then JW_Bool(w, "claim_draw", True)
    Return SendRequest(w, "move")
End Function

Function Online_Resign() As String
    Return GameRequest("resign")
End Function

Function Online_OfferDraw() As String
    Return GameRequest("offer_draw")
End Function

Function Online_AcceptDraw() As String
    Return GameRequest("accept_draw")
End Function

Function Online_DeclineDraw() As String
    Return GameRequest("decline_draw")
End Function

Function Online_ClaimDraw() As String
    Return GameRequest("claim_draw")
End Function

Function Online_Abort() As String
    Return GameRequest("abort")
End Function

Function Online_RequestGameState() As String
    Return GameRequest("game_state")
End Function

Function Online_LobbySubscribe() As String
    Dim As JsonWriter w
    StartRequest(w, "lobby_subscribe")
    Return SendRequest(w, "lobby_subscribe")
End Function

Function Online_LobbyUnsubscribe() As String
    Dim As JsonWriter w
    StartRequest(w, "lobby_unsubscribe")
    Return SendRequest(w, "lobby_unsubscribe")
End Function

Function Online_LoggedIn() As Boolean
    Return OLMyName <> "" AndAlso OLStatus = OL_READY
End Function

Function Online_MyName() As String
    Return OLMyName
End Function

Function Online_Waiting() As Boolean
    Return OLWaiting AndAlso OLStatus = OL_READY
End Function

Function Online_LobbyCount() As Integer
    Return OLLobbyCount
End Function

Function Online_LobbyTotal() As Integer
    Return OLLobbyTotal
End Function

Function Online_LobbyEntry(ByVal index As Integer) As OnlineLobbyEntry Ptr
    If index < 0 OrElse index >= OLLobbyCount Then Return 0
    Return @OLLobby(index)
End Function

Sub Online_DebugInject(ByRef text As Const String, ByVal markReady As Boolean = True)
    If markReady Then
        OLStatus = OL_READY
        If OLHost = "" Then OLHost = "freedomnet.tech"
        OLStatusText = "Connected to " & OLHost
    End If
    HandleMessage(text)
End Sub

Private Function Credentials(ByRef rtype As Const String, ByRef username As Const String, _
                             ByRef password As Const String) As String
    Dim As JsonWriter w
    StartRequest(w, rtype)
    JW_Str(w, "username", username)
    JW_Str(w, "password", password)
    Return SendRequest(w, rtype)
End Function

Function Online_Register(ByRef username As Const String, ByRef password As Const String) As String
    Return Credentials("register", username, password)
End Function

Function Online_Login(ByRef username As Const String, ByRef password As Const String) As String
    Return Credentials("login", username, password)
End Function

Function Online_Resume(ByRef token As Const String) As String
    Dim As JsonWriter w
    StartRequest(w, "resume")
    JW_Str(w, "session_token", token)
    Return SendRequest(w, "resume")
End Function

Function Online_Logout() As String
    Dim As JsonWriter w
    StartRequest(w, "logout")
    Return SendRequest(w, "logout")
End Function

Function Online_DeleteAccount(ByRef password As Const String) As String
    Dim As JsonWriter w
    StartRequest(w, "delete_account")
    JW_Str(w, "password", password)
    Return SendRequest(w, "delete_account")
End Function

Function Online_MyKind() As String
    Return OLMyKind
End Function

Function Online_MyRating() As Integer
    Return OLMyRating
End Function

Function Online_MyProvisional() As Boolean
    Return OLMyProvisional
End Function

Function Online_SessionToken() As String
    Return OLToken
End Function

Function Online_RequestProfile(ByRef username As Const String) As String
    Dim As JsonWriter w
    StartRequest(w, "profile")
    If username <> "" Then JW_Str(w, "username", username)
    Return SendRequest(w, "profile")
End Function

Function Online_RequestHistory(ByVal offset As Integer) As String
    Dim As JsonWriter w
    StartRequest(w, "history")
    JW_Int(w, "offset", IIf(offset < 0, 0, offset))
    JW_Int(w, "limit", 20)
    Return SendRequest(w, "history")
End Function

Function Online_RequestGameRecord(ByRef gameId As Const String) As String
    Dim As JsonWriter w
    StartRequest(w, "game_record")
    JW_Str(w, "game_id", gameId)
    Return SendRequest(w, "game_record")
End Function

Function Online_Profile() As OnlineProfile Ptr
    Return @OLProfile
End Function

Function Online_HistoryCount() As Integer
    Return OLHistoryCount
End Function

Function Online_HistoryOffset() As Integer
    Return OLHistoryOffset
End Function

Function Online_HistoryEntry(ByVal index As Integer) As OnlineGameSummary Ptr
    If index < 0 OrElse index >= OLHistoryCount Then Return 0
    Return @OLHistory(index)
End Function

Private Function ChallengeRequest(ByRef rtype As Const String, ByRef cid As Const String) As String
    Dim As JsonWriter w
    StartRequest(w, rtype)
    JW_Str(w, "challenge_id", cid)
    Return SendRequest(w, rtype)
End Function

Function Online_Challenge(ByRef opponent As Const String, ByVal minutes As Integer, _
                          ByVal incrementSec As Integer, ByVal rated As Boolean) As String
    Dim As JsonWriter w
    StartRequest(w, "challenge")
    JW_Str(w, "opponent", opponent)
    JW_BeginObj(w, "time_control")
    JW_Int(w, "initial_seconds", minutes * 60)
    JW_Int(w, "increment_seconds", incrementSec)
    JW_End(w)
    JW_Bool(w, "rated", rated)
    Return SendRequest(w, "challenge")
End Function

Function Online_ChallengeAccept(ByRef challengeId As Const String) As String
    OLAcceptingId = challengeId
    Return ChallengeRequest("challenge_accept", challengeId)
End Function

Function Online_ChallengeDecline(ByRef challengeId As Const String) As String
    Return ChallengeRequest("challenge_decline", challengeId)
End Function

Function Online_ChallengeCancel(ByRef challengeId As Const String) As String
    Return ChallengeRequest("challenge_cancel", challengeId)
End Function

Function Online_IncomingCount() As Integer
    Return OLIncomingCount
End Function

Function Online_Incoming(ByVal index As Integer) As OnlineChallenge Ptr
    If index < 0 OrElse index >= OLIncomingCount Then Return 0
    Return @OLIncoming(index)
End Function

Function Online_Outgoing() As OnlineChallenge Ptr
    Return @OLOutgoing
End Function

Function Online_ClaimAbandonment(ByVal win As Boolean) As String
    If OLGame.gameId = "" Then Return ""
    Dim As JsonWriter w
    StartRequest(w, "claim_abandonment")
    JW_Str(w, "game_id", OLGame.gameId)
    JW_Str(w, "outcome", IIf(win, "win", "draw"))
    Return SendRequest(w, "claim_abandonment")
End Function

Function Online_RequestLeaderboard(ByVal offset As Integer) As String
    Dim As JsonWriter w
    StartRequest(w, "leaderboard")
    JW_Int(w, "offset", IIf(offset < 0, 0, offset))
    JW_Int(w, "limit", 20)
    Return SendRequest(w, "leaderboard")
End Function

Function Online_LeaderCount() As Integer
    Return OLLeaderCount
End Function

Function Online_LeaderTotal() As Integer
    Return OLLeaderTotal
End Function

Function Online_LeaderOffset() As Integer
    Return OLLeaderOffset
End Function

Function Online_LeaderEntry(ByVal index As Integer) As OnlineLeaderEntry Ptr
    If index < 0 OrElse index >= OLLeaderCount Then Return 0
    Return @OLLeaders(index)
End Function

Function Online_Reconnecting() As Boolean
    Return OLReconnecting
End Function

Function Online_Ping() As String
    Dim As JsonWriter w
    StartRequest(w, "ping")
    Return SendRequest(w, "ping")
End Function

'' ---------------------------------------------------------------------
'' Current game
'' ---------------------------------------------------------------------
Function Online_Game() As OnlineGame Ptr
    Return @OLGame
End Function

Function Online_ClockMs(ByRef colour As Const String, ByVal now As Double) As LongInt
    Dim As LongInt ms = IIf(colour = "w", OLGame.whiteMs, OLGame.blackMs)
    If OLGame.status = "active" AndAlso OLGame.running = colour Then
        ms -= CLngInt((now - OLGame.clockAt) * 1000)
    End If
    If ms < 0 Then ms = 0
    Return ms
End Function

Sub Online_ClearGame()
    Dim As OnlineGame empty
    OLGame = empty
End Sub
