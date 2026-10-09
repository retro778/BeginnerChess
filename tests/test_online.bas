'' =====================================================================
'' BeginnerChess - tests/test_online.bas
'' End-to-end test of the client network stack (json + net + online)
'' against a running BeginnerChess server. Started by the server test suite
'' (server/tests/test_fb_client.py), which provides a TLS server, a test CA
'' (BEGINNERCHESS_CAFILE) and an opponent bot.
''
''   test_online URL                play a complete game (fool's mate)
''   test_online --echo URL         message round trip with any WebSocket echo service
''   test_online --cancel-test URL  cancel a hanging connect, then connect to URL
''   test_online --expect-fail URL  the connection must be refused
''                                  (prints the reason; used for certificate checks)
'' =====================================================================
#include once "../modules/online.bi"

Dim Shared TestsPassed As Integer = 0
Dim Shared TestsFailed As Integer = 0

Sub Check(ByVal ok As Boolean, ByRef testName As Const String, ByRef detail As Const String = "")
    If ok Then
        TestsPassed += 1
    Else
        TestsFailed += 1
        Print "  FAIL: " & testName;
        If detail <> "" Then Print "  (" & detail & ")" Else Print
    End If
End Sub

'' Runs the update loop until an event of the given kind arrives (or timeout).
'' Other events are printed for the log.
Function WaitEvent(ByRef kind As Const String, ByRef ev As OnlineEvent, ByVal seconds As Double = 10) As Boolean
    Dim As Double t0 = Timer
    Do While Timer - t0 < seconds
        Online_Update(Timer)
        Do While Online_NextEvent(ev)
            If ev.kind = kind Then Return True
            If ev.kind = "error" Then Print "  (event error " & ev.code & ": " & ev.message & ")"
            If ev.kind = "connection_lost" OrElse ev.kind = "connection_closed" Then
                If kind <> ev.kind Then Return False
            End If
        Loop
        Sleep 5, 1
    Loop
    Return False
End Function

Function WaitStatus(ByVal wanted As Integer, ByVal seconds As Double) As Boolean
    Dim As Double t0 = Timer
    Do While Timer - t0 < seconds
        Online_Update(Timer)
        If Online_Status() = wanted Then Return True
        If Online_Status() = OL_LOST Then Return False
        Sleep 5, 1
    Loop
    Return False
End Function

Sub ExpectFailure(ByRef url As Const String)
    '' The connection must never open. The reason must name the certificate - but
    '' public test servers sometimes reset or drop a connection before their
    '' certificate is even seen; such network failures are retried (3 attempts).
    Print "Connection that must be refused: " & url
    Dim As String e
    Dim As Integer attempt
    For attempt = 1 To 3
        If Not Online_Connect(url, e) Then
            Print "  refused at once: " & e
            Check True, "refused"
            Exit Sub
        End If
        Dim As Double t0 = Timer
        Do While Timer - t0 < 30 AndAlso Online_Status() <> OL_LOST AndAlso Online_Status() <> OL_READY
            Online_Update(Timer)
            Sleep 5, 1
        Loop
        Dim As Integer st = Online_Status()
        Dim As String reason = Online_StatusText()
        Online_Disconnect()
        If st <> OL_LOST Then
            Check False, "connection refused", "status " & st & ": " & reason      '' never retried
            Exit Sub
        End If
        Print "  reason: " & reason
        If InStr(LCase(reason), "certificate") > 0 Then
            Check True, "connection refused"
            Check True, "the reason names the certificate"
            Exit Sub
        End If
        If attempt < 3 Then Print "  (a network problem, not the certificate - trying again)"
        Sleep 2000, 1
    Next
    Check True, "connection refused"
    Check False, "the reason names the certificate", _
          "the test server could not be reached properly 3 times (a network problem; the connection " & _
          "was refused every time) - please run the check again later"
End Sub

Sub PlayGame(ByRef url As Const String)
    Print "Library: " & Net_LibraryInfo()
    Dim As String e
    Dim As OnlineEvent ev
    Check Online_Connect(url, e), "connect started", e
    Check WaitStatus(OL_READY, 15), "secure connection + hello", Online_StatusText()
    Check InStr(Online_StatusText(), "Connected to") > 0, "status text", Online_StatusText()
    Check Online_Feature("guests"), "server offers guest play"

    Dim As String rid = Online_LoginGuest("FBTester")
    Check rid <> "", "login request sent"
    Check WaitEvent("logged_in", ev) AndAlso ev.requestId = rid AndAlso ev.requestType = "login_guest", _
          "logged in as guest", ev.message
    Online_QuickMatch(10, 0, False)
    Check WaitEvent("game_started", ev, 15), "opponent found, game started"
    Dim As OnlineGame Ptr g = Online_Game()
    Check g->gameId <> "" AndAlso (g->myColor = "w" OrElse g->myColor = "b"), "game snapshot", g->myColor
    '' The start snapshot itself (the opponent may already have moved since).
    Dim As JsonDoc sd
    Dim As String perr
    Check Json_Parse(sd, ev.text, perr), "game_started is valid JSON", perr
    Dim As Long sg = Json_Member(sd, 0, "game")
    Check Json_GetInt(sd, Json_Member(sd, sg, "time_control"), "initial_seconds") = 600 AndAlso _
          Json_GetInt(sd, Json_Member(sd, sg, "clock"), "white_ms") = 600000 AndAlso Json_GetInt(sd, sg, "ply") = 0, _
          "start snapshot: time control, clocks, no moves"
    Check g->initialSec = 600 AndAlso g->incrementSec = 0, "time control stored"
    Print "  playing " & IIf(g->myColor = "w", "white", "black") & ": " & g->whiteName & " vs " & g->blackName

    '' Fool's mate; each side plays its own moves.
    Dim As String script(0 To 3) = {"f2f3", "e7e5", "g2g4", "d8h4"}
    Dim As Integer illegalTried = 0
    Dim As Double t0 = Timer
    Do While g->status = "active" AndAlso Timer - t0 < 30
        Online_Update(Timer)
        Do While Online_NextEvent(ev)
            If ev.kind = "error" Then
                If illegalTried = 1 AndAlso ev.requestType = "move" Then
                    Check ev.code = "illegal_move", "illegal move refused by the server", ev.code
                    illegalTried = 2
                Else
                    Print "  (error " & ev.code & ": " & ev.message & ")"
                End If
            End If
        Loop
        Dim As String toMove = g->turn
        If g->status = "active" AndAlso toMove = g->myColor AndAlso Online_PendingCount() = 0 AndAlso g->ply < 4 Then
            If illegalTried = 0 Then
                Online_SendMove("e2e5")                          '' never legal
                illegalTried = 1
            ElseIf illegalTried = 2 Then
                Online_SendMove(script(g->ply))
            End If
        End If
        Sleep 5, 1
    Loop
    Check illegalTried = 2, "the illegal-move check ran"
    Check g->status = "finished", "game finished", g->status
    Check g->result = "0-1" AndAlso g->termination = "checkmate", "black won by checkmate", g->result & " " & g->termination
    Check g->ply = 4 AndAlso g->sans(3) = "Qh4#", "move list from the server", g->ply & " " & IIf(g->ply = 4, g->sans(3), "")
    Check InStr(g->pgn, "1. f3 e5 2. g4 Qh4# 0-1") > 0, "PGN received"
    Check g->fen = "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3", "final position", g->fen
    '' The clocks ran only for moves 3 and 4 (after both first moves) and stopped at the end.
    Dim As LongInt cw = Online_ClockMs("w", Timer), cb = Online_ClockMs("b", Timer)
    Check cw > 590000 AndAlso cw <= 600000 AndAlso cb > 590000 AndAlso cb <= 600000, "clock values", cw & " " & cb
    Sleep 50, 1
    Check Online_ClockMs("w", Timer) = cw AndAlso Online_ClockMs("b", Timer) = cb, "clocks stopped after the game"

    '' Heartbeat request and orderly goodbye.
    rid = Online_Ping()
    Check WaitEvent("pong", ev) AndAlso ev.requestId = rid, "ping answered"
    Online_Disconnect()
    Check Online_Status() = OL_OFFLINE, "disconnected"
    Check Net_State() = NET_CLOSED, "network closed"
End Sub

Sub CancelWhileConnecting(ByRef url As Const String)
    Print "Cancelling a connection that hangs, then connecting properly"
    Dim As String e
    '' 10.255.255.1 is not routed: the connect would hang until its timeout.
    Check Online_Connect("wss://10.255.255.1:9/chess/ws", e), "slow connect started", e
    Sleep 200, 1
    Online_Update(Timer)
    Check Online_Status() = OL_CONNECTING, "still connecting", Str(Online_Status())
    Dim As Double t0 = Timer
    Online_Disconnect()
    Check Timer - t0 < 0.2, "cancel returns at once (the GUI never waits)", Str(Timer - t0)
    Check Online_Status() = OL_OFFLINE, "offline after cancel"
    If url = "-" Then Exit Sub                     '' no server to reconnect to
    '' A new connection must not be disturbed by the abandoned one.
    Check Online_Connect(url, e), "new connect started", e
    Check WaitStatus(OL_READY, 15), "new connection ready", Online_StatusText()
    Dim As OnlineEvent ev
    Dim As String rid = Online_Ping()
    Check WaitEvent("pong", ev) AndAlso ev.requestId = rid, "new connection works"
    Online_Disconnect()
End Sub

Sub EchoTest(ByRef url As Const String)
    '' Any WebSocket echo service: checks TLS + WebSocket without our server.
    Print "Echo test: " & url & "  (" & Net_LibraryInfo() & ")"
    Dim As String e
    Check Net_Connect(url, e), "connect started", e
    Dim As Double t0 = Timer
    Do While Net_State() = NET_CONNECTING AndAlso Timer - t0 < 15
        Sleep 10, 1
    Loop
    Check Net_State() = NET_OPEN, "secure WebSocket open", Net_Error()
    Dim As String sent = "BeginnerChess echo " & Int(Rnd * 1000000), got, reply
    Net_Send(sent)
    t0 = Timer
    Do While Timer - t0 < 10
        If Net_Receive(got) Then
            If got = sent Then reply = got : Exit Do
        End If
        Sleep 10, 1
    Loop
    Check reply = sent, "message echoed", reply
    Net_Disconnect()
    Check Net_State() = NET_CLOSED, "closed"
End Sub

Print "BeginnerChess online client test"
If Command(1) = "--echo" Then
    Randomize Timer
    EchoTest(Command(2))
ElseIf Command(1) = "--cancel-test" Then
    CancelWhileConnecting(Command(2))
ElseIf Command(1) = "--expect-fail" Then
    ExpectFailure(Command(2))
ElseIf Command(1) <> "" Then
    PlayGame(Command(1))
Else
    Print "usage: test_online URL | --expect-fail URL"
    End 2
End If
Net_Shutdown()
Print
Print "Passed: " & TestsPassed & "   Failed: " & TestsFailed
If TestsFailed > 0 Then End 1
End 0
