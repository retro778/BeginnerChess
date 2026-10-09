'' =====================================================================
'' BeginnerChess - net.bas
'' Secure WebSocket client. See net.bi for the design.
''
'' Every connection attempt gets a NetConn object and a generation number.
'' Its worker thread owns the object and frees it at the end. When the
'' program closes a connection that is still being set up (which can block
'' inside the library for several seconds), the worker is detached and its
'' generation becomes stale: from then on it cannot touch the queues or the
'' state any more, cleans up quietly and ends - the GUI never waits for it.
'' =====================================================================
#include once "net.bi"
#include once "fbthread.bi"        '' ThreadDetach

Type NetConn
    generation As Integer
    secure     As Boolean
    host       As String
    port       As Integer
    path       As String
#ifdef __FB_WIN32__
    hSession    As Any Ptr
    hConnection As Any Ptr
    hRequest    As Any Ptr
    hSocket     As Any Ptr
    sendThread  As Any Ptr
#else
    curl        As Any Ptr
#endif
End Type

'' ---------------------------------------------------------------------
'' Shared state (protected by NetLock)
'' ---------------------------------------------------------------------
Dim Shared NetLock As Any Ptr
Dim Shared NetWake As Any Ptr            '' condition: something to send / stop
Dim Shared NetThread As Any Ptr
Dim Shared NetCurrent As NetConn Ptr     '' the connection of the current generation
Dim Shared NetGeneration As Integer
Dim Shared NetStateValue As Integer = NET_IDLE
Dim Shared NetErrorText As String
Dim Shared NetCloseCodeValue As Integer
Dim Shared NetStopFlag As Boolean
Dim Shared NetLiveWorkers As Integer      '' worker threads still running (also detached ones)

Dim Shared InQ(0 To NET_IN_QUEUE - 1) As String
Dim Shared InHead As Integer, InCount As Integer
Dim Shared OutQ(0 To NET_OUT_QUEUE - 1) As String
Dim Shared OutHead As Integer, OutCount As Integer

Dim Shared NetLibTried As Boolean
Dim Shared NetLibOk As Boolean
Dim Shared NetLibText As String

Private Sub EnsureLock()
    If NetLock = 0 Then NetLock = MutexCreate()
    If NetWake = 0 Then NetWake = CondCreate()
End Sub

'' State change by the worker of generation gen (ignored if stale).
Private Sub SetState(ByVal gen As Integer, ByVal st As Integer, ByRef errText As Const String = "")
    MutexLock(NetLock)
    If gen = NetGeneration Then
        If st = NET_FAILED AndAlso NetStopFlag Then st = NET_CLOSED   '' failure after our own stop
        NetStateValue = st
        If errText <> "" Then NetErrorText = errText
    End If
    MutexUnlock(NetLock)
End Sub

Private Sub SetCloseCode(ByVal gen As Integer, ByVal code As Integer)
    MutexLock(NetLock)
    If gen = NetGeneration Then NetCloseCodeValue = code
    MutexUnlock(NetLock)
End Sub

Private Function StopRequested(ByVal gen As Integer) As Boolean
    MutexLock(NetLock)
    Dim As Boolean s = NetStopFlag OrElse gen <> NetGeneration
    MutexUnlock(NetLock)
    Return s
End Function

Private Function IsOpen(ByVal gen As Integer) As Boolean
    MutexLock(NetLock)
    Dim As Boolean o = (gen = NetGeneration) AndAlso NetStateValue = NET_OPEN
    MutexUnlock(NetLock)
    Return o
End Function

'' A complete message from the server. False if the queue overflowed.
Private Function PushIncoming(ByVal gen As Integer, ByRef text As Const String) As Boolean
    MutexLock(NetLock)
    If gen <> NetGeneration Then
        MutexUnlock(NetLock)
        Return True                                   '' stale: silently dropped
    End If
    If InCount >= NET_IN_QUEUE Then
        MutexUnlock(NetLock)
        Return False
    End If
    InQ((InHead + InCount) Mod NET_IN_QUEUE) = text
    InCount += 1
    MutexUnlock(NetLock)
    Return True
End Function

Private Function PopOutgoing(ByVal gen As Integer, ByRef text As String) As Boolean
    MutexLock(NetLock)
    If gen <> NetGeneration OrElse OutCount = 0 Then
        MutexUnlock(NetLock)
        Return False
    End If
    text = OutQ(OutHead)
    OutQ(OutHead) = ""
    OutHead = (OutHead + 1) Mod NET_OUT_QUEUE
    OutCount -= 1
    MutexUnlock(NetLock)
    Return True
End Function

Private Function OutgoingWaiting(ByVal gen As Integer) As Boolean
    MutexLock(NetLock)
    Dim As Boolean w = (gen = NetGeneration) AndAlso OutCount > 0
    MutexUnlock(NetLock)
    Return w
End Function

'' Ownership of a NetConn: a worker frees its object only when it has
'' become stale (detached by Net_Disconnect); otherwise the main thread frees
'' it after ThreadWait. So the main thread can always use NetCurrent safely.
Private Sub FinishWorker(ByVal c As NetConn Ptr)
    MutexLock(NetLock)
    Dim As Boolean stale = (c->generation <> NetGeneration)
    NetLiveWorkers -= 1
    MutexUnlock(NetLock)
    If stale Then Delete c
End Sub

Private Sub ClearQueues()
    Dim As Integer k
    For k = 0 To NET_IN_QUEUE - 1 : InQ(k) = "" : Next
    For k = 0 To NET_OUT_QUEUE - 1 : OutQ(k) = "" : Next
    InHead = 0 : InCount = 0 : OutHead = 0 : OutCount = 0
End Sub

'' ---------------------------------------------------------------------
'' URL
'' ---------------------------------------------------------------------
Function Net_ParseUrl(ByRef url As Const String, ByRef secure As Boolean, ByRef host As String, _
                      ByRef port As Integer, ByRef path As String, ByRef errMsg As String) As Boolean
    Dim As String u = Trim(url)
    errMsg = ""
    host = "" : path = "" : port = 0 : secure = False
    If Len(u) = 0 OrElse Len(u) > 256 Then
        errMsg = "Please enter a server address like wss://freedomnet.tech/chess/ws"
        Return False
    End If
    Dim As String rest
    If LCase(Left(u, 6)) = "wss://" Then
        secure = True : rest = Mid(u, 7) : port = 443
    ElseIf LCase(Left(u, 5)) = "ws://" Then
        secure = False : rest = Mid(u, 6) : port = 80
    Else
        errMsg = "The server address must start with wss://"
        Return False
    End If
    Dim As Integer slash = InStr(rest, "/")
    Dim As String hostPort = IIf(slash > 0, Left(rest, slash - 1), rest)
    path = IIf(slash > 0, Mid(rest, slash), "/")
    If InStr(hostPort, "@") > 0 Then
        errMsg = "User names in server addresses are not supported."
        Return False
    End If
    host = hostPort
    If Left(hostPort, 1) = "[" Then                         '' [IPv6]:port
        Dim As Integer rb = InStr(hostPort, "]")
        If rb = 0 Then
            errMsg = "Invalid server address."
            Return False
        End If
        host = Mid(hostPort, 2, rb - 2)
        Dim As String after = Mid(hostPort, rb + 1)
        If Left(after, 1) = ":" Then
            Dim As String ps = Mid(after, 2)
            If Len(ps) = 0 OrElse Len(ps) > 5 OrElse ps <> Str(ValInt(ps)) Then
                errMsg = "Invalid port in the server address."
                Return False
            End If
            port = ValInt(ps)
        ElseIf after <> "" Then
            errMsg = "Invalid server address."
            Return False
        End If
    Else
        Dim As Integer colon = InStr(hostPort, ":")
        If colon > 0 Then
            host = Left(hostPort, colon - 1)
            Dim As String ps = Mid(hostPort, colon + 1)
            If Len(ps) = 0 OrElse Len(ps) > 5 OrElse ps <> Str(ValInt(ps)) Then
                errMsg = "Invalid port in the server address."
                Return False
            End If
            port = ValInt(ps)
        End If
    End If
    If host = "" OrElse port < 1 OrElse port > 65535 Then
        errMsg = "Invalid server address."
        Return False
    End If
    Dim As Integer k
    For k = 0 To Len(host) - 1
        Dim As Integer c = host[k]
        If Not ((c >= 48 AndAlso c <= 58) OrElse (c >= 65 AndAlso c <= 90) OrElse (c >= 97 AndAlso c <= 122) _
                OrElse c = 45 OrElse c = 46) Then
            errMsg = "Invalid characters in the server name."
            Return False
        End If
    Next
    For k = 0 To Len(path) - 1
        If path[k] <= 32 OrElse path[k] >= 127 Then
            errMsg = "Invalid characters in the server address."
            Return False
        End If
    Next
    If Not secure Then
        Dim As String lh = LCase(host)
        If lh <> "localhost" AndAlso lh <> "127.0.0.1" AndAlso lh <> "::1" Then
            errMsg = "Only secure connections (wss://) are allowed."
            Return False
        End If
    End If
    Return True
End Function

'' Copies n bytes into a new string.
Private Function BytesToString(ByVal src As UByte Ptr, ByVal n As UInteger) As String
    Dim As String s = Space(n)
    Dim As UInteger k
    For k = 0 To n - 1
        s[k] = src[k]
    Next
    Return s
End Function

'' =====================================================================
#ifdef __FB_WIN32__
'' =====================================================================
'' Windows: WinHTTP (stdcall). Declarations follow winhttp.h.
'' =====================================================================
Type WH_Open As Function Stdcall (ByVal agent As WString Ptr, ByVal access As ULong, ByVal proxy As WString Ptr, _
                                  ByVal bypass As WString Ptr, ByVal flags As ULong) As Any Ptr
Type WH_SetTimeouts As Function Stdcall (ByVal h As Any Ptr, ByVal r As Long, ByVal c As Long, _
                                         ByVal s As Long, ByVal rc As Long) As Long
Type WH_Connect As Function Stdcall (ByVal h As Any Ptr, ByVal server As WString Ptr, ByVal port As UShort, _
                                     ByVal reserved As ULong) As Any Ptr
Type WH_OpenRequest As Function Stdcall (ByVal h As Any Ptr, ByVal verb As WString Ptr, ByVal obj As WString Ptr, _
                                         ByVal version As WString Ptr, ByVal referrer As WString Ptr, _
                                         ByVal accept As Any Ptr, ByVal flags As ULong) As Any Ptr
Type WH_SetOption As Function Stdcall (ByVal h As Any Ptr, ByVal opt As ULong, ByVal buf As Any Ptr, _
                                       ByVal length As ULong) As Long
Type WH_SendRequest As Function Stdcall (ByVal h As Any Ptr, ByVal headers As WString Ptr, ByVal hlen As ULong, _
                                         ByVal opt As Any Ptr, ByVal olen As ULong, ByVal total As ULong, _
                                         ByVal ctx As UInteger) As Long
Type WH_ReceiveResponse As Function Stdcall (ByVal h As Any Ptr, ByVal reserved As Any Ptr) As Long
Type WH_QueryHeaders As Function Stdcall (ByVal h As Any Ptr, ByVal level As ULong, ByVal hname As WString Ptr, _
                                          ByVal buf As Any Ptr, ByVal buflen As ULong Ptr, ByVal index As ULong Ptr) As Long
Type WH_CompleteUpgrade As Function Stdcall (ByVal h As Any Ptr, ByVal ctx As UInteger) As Any Ptr
Type WH_WsSend As Function Stdcall (ByVal h As Any Ptr, ByVal btype As Long, ByVal buf As Any Ptr, _
                                    ByVal length As ULong) As ULong
Type WH_WsReceive As Function Stdcall (ByVal h As Any Ptr, ByVal buf As Any Ptr, ByVal length As ULong, _
                                       ByVal got As ULong Ptr, ByVal btype As Long Ptr) As ULong
Type WH_WsShutdown As Function Stdcall (ByVal h As Any Ptr, ByVal status As UShort, ByVal reason As Any Ptr, _
                                        ByVal length As ULong) As ULong
Type WH_WsQueryClose As Function Stdcall (ByVal h As Any Ptr, ByVal status As UShort Ptr, ByVal reason As Any Ptr, _
                                          ByVal length As ULong, ByVal consumed As ULong Ptr) As ULong
Type WH_CloseHandle As Function Stdcall (ByVal h As Any Ptr) As Long
Type K32_GetLastError As Function Stdcall () As ULong

Dim Shared hWinHttp As Any Ptr, hKernel As Any Ptr
Dim Shared pOpen As WH_Open, pSetTimeouts As WH_SetTimeouts, pConnect As WH_Connect
Dim Shared pOpenRequest As WH_OpenRequest, pSetOption As WH_SetOption, pSendRequest As WH_SendRequest
Dim Shared pReceiveResponse As WH_ReceiveResponse, pQueryHeaders As WH_QueryHeaders
Dim Shared pCompleteUpgrade As WH_CompleteUpgrade, pWsSend As WH_WsSend, pWsReceive As WH_WsReceive
Dim Shared pWsShutdown As WH_WsShutdown, pWsQueryClose As WH_WsQueryClose, pCloseHandle As WH_CloseHandle
Dim Shared pGetLastError As K32_GetLastError

Const WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0
Const WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY = 4
Const WINHTTP_FLAG_SECURE = &h00800000
Const WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET = 114
Const WINHTTP_QUERY_STATUS_CODE = 19
Const WINHTTP_QUERY_FLAG_NUMBER = &h20000000
Const WS_BINARY_MESSAGE = 0, WS_BINARY_FRAGMENT = 1, WS_UTF8_MESSAGE = 2, WS_UTF8_FRAGMENT = 3, WS_CLOSE = 4
Const ERROR_WINHTTP_TIMEOUT = 12002
Const ERROR_WINHTTP_NAME_NOT_RESOLVED = 12007
Const ERROR_WINHTTP_OPERATION_CANCELLED = 12017
Const ERROR_WINHTTP_CANNOT_CONNECT = 12029
Const ERROR_WINHTTP_CONNECTION_ERROR = 12030
Const ERROR_WINHTTP_SECURE_FAILURE = 12175

Function Net_Init() As Boolean
    If NetLibTried Then Return NetLibOk
    NetLibTried = True
    EnsureLock()
    hWinHttp = DyLibLoad("winhttp.dll")
    hKernel = DyLibLoad("kernel32.dll")
    If hWinHttp = 0 OrElse hKernel = 0 Then
        NetLibText = "WinHTTP (winhttp.dll) is not available on this computer."
        Return False
    End If
    pOpen = DyLibSymbol(hWinHttp, "WinHttpOpen")
    pSetTimeouts = DyLibSymbol(hWinHttp, "WinHttpSetTimeouts")
    pConnect = DyLibSymbol(hWinHttp, "WinHttpConnect")
    pOpenRequest = DyLibSymbol(hWinHttp, "WinHttpOpenRequest")
    pSetOption = DyLibSymbol(hWinHttp, "WinHttpSetOption")
    pSendRequest = DyLibSymbol(hWinHttp, "WinHttpSendRequest")
    pReceiveResponse = DyLibSymbol(hWinHttp, "WinHttpReceiveResponse")
    pQueryHeaders = DyLibSymbol(hWinHttp, "WinHttpQueryHeaders")
    pCompleteUpgrade = DyLibSymbol(hWinHttp, "WinHttpWebSocketCompleteUpgrade")
    pWsSend = DyLibSymbol(hWinHttp, "WinHttpWebSocketSend")
    pWsReceive = DyLibSymbol(hWinHttp, "WinHttpWebSocketReceive")
    pWsShutdown = DyLibSymbol(hWinHttp, "WinHttpWebSocketShutdown")
    pWsQueryClose = DyLibSymbol(hWinHttp, "WinHttpWebSocketQueryCloseStatus")
    pCloseHandle = DyLibSymbol(hWinHttp, "WinHttpCloseHandle")
    pGetLastError = DyLibSymbol(hKernel, "GetLastError")
    If pOpen = 0 OrElse pConnect = 0 OrElse pOpenRequest = 0 OrElse pSetOption = 0 OrElse pSendRequest = 0 _
       OrElse pReceiveResponse = 0 OrElse pCompleteUpgrade = 0 OrElse pWsSend = 0 OrElse pWsReceive = 0 _
       OrElse pWsShutdown = 0 OrElse pCloseHandle = 0 OrElse pGetLastError = 0 OrElse pSetTimeouts = 0 _
       OrElse pQueryHeaders = 0 OrElse pWsQueryClose = 0 Then
        NetLibText = "This version of Windows has no WebSocket support (Windows 8 or newer is needed)."
        Return False
    End If
    NetLibText = "WinHTTP (Windows)"
    NetLibOk = True
    Return True
End Function

Private Function WinErrorText(ByVal code As ULong) As String
    Select Case code
    Case ERROR_WINHTTP_NAME_NOT_RESOLVED : Return "The server name could not be found. Is the computer online?"
    Case ERROR_WINHTTP_CANNOT_CONNECT : Return "The server cannot be reached right now."
    Case ERROR_WINHTTP_TIMEOUT : Return "The server did not answer in time."
    Case ERROR_WINHTTP_SECURE_FAILURE : Return "The server's security certificate could not be verified."
    Case ERROR_WINHTTP_CONNECTION_ERROR : Return "The connection to the server was lost."
    Case Else : Return "Network error " & code & "."
    End Select
End Function

'' Closes the handles of c exactly once (may be called from both threads).
Private Sub CloseConnHandles(ByVal c As NetConn Ptr)
    MutexLock(NetLock)
    Dim As Any Ptr hs = c->hSocket, hr = c->hRequest, hc = c->hConnection, hsn = c->hSession
    c->hSocket = 0 : c->hRequest = 0 : c->hConnection = 0 : c->hSession = 0
    MutexUnlock(NetLock)
    If hs <> 0 Then pCloseHandle(hs)
    If hr <> 0 Then pCloseHandle(hr)
    If hc <> 0 Then pCloseHandle(hc)
    If hsn <> 0 Then pCloseHandle(hsn)
End Sub

'' Sender thread: sends queued messages while the receive loop waits
'' (WinHTTP allows one send and one receive at the same time).
Private Sub SenderThread(ByVal param As Any Ptr)
    Dim As NetConn Ptr c = param
    Dim As Integer gen = c->generation
    Do
        MutexLock(NetLock)
        Do While OutCount = 0 AndAlso Not NetStopFlag AndAlso gen = NetGeneration AndAlso NetStateValue = NET_OPEN
            CondWait(NetWake, NetLock)
        Loop
        Dim As Boolean quit = NetStopFlag OrElse gen <> NetGeneration OrElse NetStateValue <> NET_OPEN
        Dim As Any Ptr hs = c->hSocket
        MutexUnlock(NetLock)
        If quit OrElse hs = 0 Then Exit Do
        Dim As String msg
        Do While PopOutgoing(gen, msg)
            Dim As ULong rc = pWsSend(hs, WS_UTF8_MESSAGE, StrPtr(msg), Len(msg))
            If rc <> 0 Then
                SetState(gen, NET_FAILED, WinErrorText(rc))
                Exit Sub
            End If
        Loop
    Loop
End Sub

Private Sub WorkerThread(ByVal param As Any Ptr)
    Dim As NetConn Ptr c = param
    Dim As Integer gen = c->generation
    Dim As WString * 64 wAgent = "BeginnerChess"
    Dim As WString * 300 wHost = c->host
    Dim As WString * 600 wPath = c->path
    Dim As WString * 8 wGet = "GET"
    Dim As String failText

    c->hSession = pOpen(@wAgent, WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, 0, 0, 0)
    If c->hSession = 0 Then c->hSession = pOpen(@wAgent, WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, 0, 0, 0)
    If c->hSession <> 0 Then
        pSetTimeouts(c->hSession, 10000, 10000, 15000, 0)     '' receive: no limit (server pings)
        c->hConnection = pConnect(c->hSession, @wHost, c->port, 0)
    End If
    If c->hConnection <> 0 Then
        c->hRequest = pOpenRequest(c->hConnection, @wGet, @wPath, 0, 0, 0, IIf(c->secure, WINHTTP_FLAG_SECURE, 0))
    End If
    Dim As Boolean ok = (c->hRequest <> 0)
    If ok Then ok = (pSetOption(c->hRequest, WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, 0, 0) <> 0)
    If ok Then ok = (pSendRequest(c->hRequest, 0, 0, 0, 0, 0, 0) <> 0)
    If ok Then ok = (pReceiveResponse(c->hRequest, 0) <> 0)
    If Not ok Then
        failText = WinErrorText(pGetLastError())
    Else
        Dim As ULong status = 0, slen = 4
        pQueryHeaders(c->hRequest, WINHTTP_QUERY_STATUS_CODE Or WINHTTP_QUERY_FLAG_NUMBER, 0, @status, @slen, 0)
        If status = 503 Then
            failText = "The server is busy. Please try again later."
        ElseIf status = 404 Then
            failText = "There is no BeginnerChess server at this address."
        ElseIf status <> 101 Then
            failText = "The server refused the connection (HTTP " & status & ")."
        Else
            Dim As Any Ptr hs = pCompleteUpgrade(c->hRequest, 0)
            MutexLock(NetLock)
            c->hSocket = hs
            MutexUnlock(NetLock)
            If hs = 0 Then failText = "The server did not accept the connection."
        End If
    End If
    If failText <> "" OrElse StopRequested(gen) Then
        CloseConnHandles(c)
        SetState(gen, IIf(failText <> "", NET_FAILED, NET_CLOSED), failText)
        FinishWorker(c)
        Exit Sub
    End If
    '' The request handle is not needed after the upgrade.
    MutexLock(NetLock)
    Dim As Any Ptr hr = c->hRequest
    c->hRequest = 0
    MutexUnlock(NetLock)
    If hr <> 0 Then pCloseHandle(hr)
    SetState(gen, NET_OPEN)
    c->sendThread = ThreadCreate(@SenderThread, c, 65536)

    '' Receive loop (blocking; ends when the server closes or the handle is closed).
    Dim As String msg
    Dim As UByte buf(0 To 65535)
    Do
        MutexLock(NetLock)
        Dim As Any Ptr hs = c->hSocket
        MutexUnlock(NetLock)
        If hs = 0 Then Exit Do
        Dim As ULong got = 0
        Dim As Long btype = 0
        Dim As ULong rc = pWsReceive(hs, @buf(0), 65536, @got, @btype)
        If rc <> 0 Then
            If rc = ERROR_WINHTTP_OPERATION_CANCELLED OrElse StopRequested(gen) Then
                SetState(gen, NET_CLOSED)
            Else
                SetState(gen, NET_FAILED, WinErrorText(rc))
            End If
            Exit Do
        End If
        If btype = WS_CLOSE Then
            Dim As UShort code = 0
            Dim As ULong consumed = 0
            Dim As UByte reason(0 To 127)
            pWsQueryClose(hs, @code, @reason(0), 123, @consumed)
            SetCloseCode(gen, code)
            SetState(gen, NET_CLOSED)
            Exit Do
        End If
        If Len(msg) + got > NET_MAX_MESSAGE Then
            SetState(gen, NET_FAILED, "The server sent too much data.")
            Exit Do
        End If
        If got > 0 Then msg &= BytesToString(@buf(0), got)
        If btype = WS_UTF8_MESSAGE OrElse btype = WS_BINARY_MESSAGE Then
            If btype = WS_UTF8_MESSAGE AndAlso Not PushIncoming(gen, msg) Then
                SetState(gen, NET_FAILED, "Too many messages from the server.")
                Exit Do
            End If
            msg = ""
        End If
    Loop
    '' Finish the sender, then release everything.
    MutexLock(NetLock)
    CondBroadcast(NetWake)
    MutexUnlock(NetLock)
    CloseConnHandles(c)
    If c->sendThread <> 0 Then ThreadWait(c->sendThread)
    FinishWorker(c)
End Sub

'' Asks an open connection to end: a close frame, then (if needed) closing
'' the handle makes the blocking receive return.
Private Sub StopOpenConnection(ByVal c As NetConn Ptr)
    MutexLock(NetLock)
    Dim As Any Ptr hs = c->hSocket
    MutexUnlock(NetLock)
    If hs <> 0 Then pWsShutdown(hs, 1000, 0, 0)
    CloseConnHandles(c)
End Sub

Private Sub LibraryCleanup()
End Sub

'' =====================================================================
#else
'' =====================================================================
'' Linux (and other Unix): libcurl
'' =====================================================================
Type CurlWsFrame
    age       As Long
    flags     As Long
    offset    As LongInt
    bytesleft As LongInt
    length    As UInteger
End Type

Type PollFd
    fd      As Long
    events  As Short
    revents As Short
End Type

Declare Function c_poll Cdecl Alias "poll" (ByVal fds As PollFd Ptr, ByVal nfds As UInteger, ByVal timeout As Long) As Long

'' Note: C "long" is 64 bits on 64-bit Linux, so long arguments of the
'' variadic curl_easy_setopt are passed as LongInt.
Type CU_GlobalInit As Function Cdecl (ByVal flags As LongInt) As Long
Type CU_GlobalCleanup As Sub Cdecl ()
Type CU_EasyInit As Function Cdecl () As Any Ptr
Type CU_EasySetopt As Function Cdecl (ByVal h As Any Ptr, ByVal opt As Long, ...) As Long
Type CU_EasyGetinfo As Function Cdecl (ByVal h As Any Ptr, ByVal info As Long, ...) As Long
Type CU_EasyPerform As Function Cdecl (ByVal h As Any Ptr) As Long
Type CU_EasyCleanup As Sub Cdecl (ByVal h As Any Ptr)
Type CU_EasyStrerror As Function Cdecl (ByVal code As Long) As ZString Ptr
Type CU_Version As Function Cdecl () As ZString Ptr
Type CU_WsRecv As Function Cdecl (ByVal h As Any Ptr, ByVal buf As Any Ptr, ByVal buflen As UInteger, _
                                  ByVal got As UInteger Ptr, ByVal meta As CurlWsFrame Ptr Ptr) As Long
Type CU_WsSend As Function Cdecl (ByVal h As Any Ptr, ByVal buf As Any Ptr, ByVal buflen As UInteger, _
                                  ByVal sent As UInteger Ptr, ByVal fragsize As LongInt, ByVal flags As ULong) As Long

Dim Shared hCurl As Any Ptr
Dim Shared pGlobalInit As CU_GlobalInit, pGlobalCleanup As CU_GlobalCleanup, pEasyInit As CU_EasyInit
Dim Shared pSetopt As CU_EasySetopt, pGetinfo As CU_EasyGetinfo, pPerform As CU_EasyPerform
Dim Shared pCleanup As CU_EasyCleanup, pStrerror As CU_EasyStrerror, pVersion As CU_Version
Dim Shared pWsRecv As CU_WsRecv, pWsSend As CU_WsSend

Const CURLE_OK = 0
Const CURLE_COULDNT_RESOLVE_HOST = 6
Const CURLE_COULDNT_CONNECT = 7
Const CURLE_OPERATION_TIMEDOUT = 28
Const CURLE_SSL_CONNECT_ERROR = 35
Const CURLE_GOT_NOTHING = 52
Const CURLE_PEER_FAILED_VERIFICATION = 60
Const CURLE_AGAIN = 81
Const CURLOPT_URL = 10002
Const CURLOPT_ERRORBUFFER = 10010
Const CURLOPT_USERAGENT = 10018
Const CURLOPT_SSL_VERIFYPEER = 64
Const CURLOPT_SSL_VERIFYHOST = 81
Const CURLOPT_CAINFO = 10065
Const CURLOPT_NOSIGNAL = 99
Const CURLOPT_CONNECT_ONLY = 141
Const CURLOPT_CONNECTTIMEOUT_MS = 156
Const CURLOPT_PROTOCOLS_STR = 10318
Const CURLINFO_RESPONSE_CODE = &h200002
Const CURLINFO_ACTIVESOCKET = &h50002C
Const CURLWS_TEXT = 1, CURLWS_BINARY = 2, CURLWS_CONT = 4, CURLWS_CLOSE = 8
Const POLLIN = 1

Function Net_Init() As Boolean
    If NetLibTried Then Return NetLibOk
    NetLibTried = True
    EnsureLock()
    '' BEGINNERCHESS_CURL=<file> forces a specific library (for testing).
    If Environ("BEGINNERCHESS_CURL") <> "" Then
        hCurl = DyLibLoad(Environ("BEGINNERCHESS_CURL"))
    Else
        hCurl = DyLibLoad("libcurl.so.4")
        If hCurl = 0 Then hCurl = DyLibLoad("libcurl.so")
    End If
    If hCurl = 0 Then
        NetLibText = "The libcurl library is not installed (package libcurl4)."
        Return False
    End If
    pGlobalInit = DyLibSymbol(hCurl, "curl_global_init")
    pGlobalCleanup = DyLibSymbol(hCurl, "curl_global_cleanup")
    pEasyInit = DyLibSymbol(hCurl, "curl_easy_init")
    pSetopt = DyLibSymbol(hCurl, "curl_easy_setopt")
    pGetinfo = DyLibSymbol(hCurl, "curl_easy_getinfo")
    pPerform = DyLibSymbol(hCurl, "curl_easy_perform")
    pCleanup = DyLibSymbol(hCurl, "curl_easy_cleanup")
    pStrerror = DyLibSymbol(hCurl, "curl_easy_strerror")
    pVersion = DyLibSymbol(hCurl, "curl_version")
    pWsRecv = DyLibSymbol(hCurl, "curl_ws_recv")
    pWsSend = DyLibSymbol(hCurl, "curl_ws_send")
    If pGlobalInit = 0 OrElse pEasyInit = 0 OrElse pSetopt = 0 OrElse pGetinfo = 0 OrElse pPerform = 0 _
       OrElse pCleanup = 0 OrElse pStrerror = 0 OrElse pVersion = 0 OrElse pGlobalCleanup = 0 Then
        NetLibText = "The libcurl library could not be used."
        Return False
    End If
    If pWsRecv = 0 OrElse pWsSend = 0 Then
        NetLibText = "The installed libcurl is too old for online play (" & *pVersion() & _
                     "; version 8.11 or newer is needed)."
        Return False
    End If
    pGlobalInit(3)                                            '' CURL_GLOBAL_ALL (once, before any thread)
    NetLibText = *pVersion()
    NetLibOk = True
    Return True
End Function

Private Function CurlErrorText(ByVal code As Long, ByRef detail As Const String) As String
    Select Case code
    Case CURLE_COULDNT_RESOLVE_HOST : Return "The server name could not be found. Is the computer online?"
    Case CURLE_COULDNT_CONNECT : Return "The server cannot be reached right now."
    Case CURLE_OPERATION_TIMEDOUT : Return "The server did not answer in time."
    Case CURLE_PEER_FAILED_VERIFICATION : Return "The server's security certificate could not be verified."
    Case CURLE_SSL_CONNECT_ERROR : Return "A secure connection could not be set up."
    Case CURLE_GOT_NOTHING : Return "The server closed the connection."
    Case Else
        Return "Network error: " & IIf(detail <> "", detail, *pStrerror(code))
    End Select
End Function

'' Sends one complete frame. False on error.
Private Function CurlSendAll(ByVal h As Any Ptr, ByVal buf As Any Ptr, ByVal length As UInteger, _
                             ByVal flags As ULong) As Boolean
    Dim As UInteger sent = 0, total = 0
    Dim As Double giveUp = Timer + 10
    Do
        Dim As Long rc = pWsSend(h, Cast(UByte Ptr, buf) + total, length - total, @sent, 0, flags)
        If rc = CURLE_OK Then
            total += sent
            If total >= length Then Return True
        ElseIf rc = CURLE_AGAIN Then
            If Timer > giveUp Then Return False
            Sleep 2, 1
        Else
            Return False
        End If
    Loop
End Function

Private Sub WorkerThread(ByVal param As Any Ptr)
    Dim As NetConn Ptr c = param
    Dim As Integer gen = c->generation
    Dim As ZString * 300 errBuf
    c->curl = pEasyInit()
    If c->curl = 0 Then
        SetState(gen, NET_FAILED, "The network library could not start.")
        FinishWorker(c)
        Exit Sub
    End If
    Dim As Any Ptr h = c->curl
    Dim As String url = IIf(c->secure, "wss://", "ws://") & _
                        IIf(InStr(c->host, ":") > 0, "[" & c->host & "]", c->host) & ":" & c->port & c->path
    Dim As String caFile = Environ("BEGINNERCHESS_CAFILE")
    pSetopt(h, CURLOPT_URL, StrPtr(url))
    pSetopt(h, CURLOPT_PROTOCOLS_STR, StrPtr("ws,wss"))
    pSetopt(h, CURLOPT_CONNECT_ONLY, CLngInt(2))             '' WebSocket mode
    pSetopt(h, CURLOPT_SSL_VERIFYPEER, CLngInt(1))           '' certificate checks: never switched off
    pSetopt(h, CURLOPT_SSL_VERIFYHOST, CLngInt(2))
    pSetopt(h, CURLOPT_NOSIGNAL, CLngInt(1))
    pSetopt(h, CURLOPT_CONNECTTIMEOUT_MS, CLngInt(10000))
    pSetopt(h, CURLOPT_USERAGENT, StrPtr("BeginnerChess"))
    pSetopt(h, CURLOPT_ERRORBUFFER, @errBuf)
    If caFile <> "" Then pSetopt(h, CURLOPT_CAINFO, StrPtr(caFile))

    Dim As Long rc = pPerform(h)
    If rc <> CURLE_OK Then
        Dim As LongInt httpCode = 0
        pGetinfo(h, CURLINFO_RESPONSE_CODE, @httpCode)
        Dim As String reason = CurlErrorText(rc, errBuf)
        If httpCode = 503 Then reason = "The server is busy. Please try again later."
        If httpCode = 404 Then reason = "There is no BeginnerChess server at this address."
        pCleanup(h)
        SetState(gen, NET_FAILED, reason)
        FinishWorker(c)
        Exit Sub
    End If
    Dim As Long sock = -1
    pGetinfo(h, CURLINFO_ACTIVESOCKET, @sock)
    If StopRequested(gen) Then
        pCleanup(h)
        SetState(gen, NET_CLOSED)
        FinishWorker(c)
        Exit Sub
    End If
    SetState(gen, NET_OPEN)

    Dim As String msg, outMsg
    Dim As UByte buf(0 To 65535)
    Dim As Boolean running = True
    Do While running
        If StopRequested(gen) Then Exit Do
        Do While PopOutgoing(gen, outMsg)                    '' send what is queued
            If Not CurlSendAll(h, StrPtr(outMsg), Len(outMsg), CURLWS_TEXT) Then
                SetState(gen, NET_FAILED, "The connection to the server was lost.")
                running = False
                Exit Do
            End If
        Loop
        If Not running Then Exit Do
        Do                                                    '' receive everything that has arrived
            Dim As UInteger got = 0
            Dim As CurlWsFrame Ptr meta = 0
            rc = pWsRecv(h, @buf(0), 65536, @got, @meta)
            If rc = CURLE_AGAIN Then Exit Do
            If rc <> CURLE_OK OrElse meta = 0 Then
                SetState(gen, NET_FAILED, "The connection to the server was lost.")
                running = False
                Exit Do
            End If
            If (meta->flags And CURLWS_CLOSE) <> 0 Then
                SetCloseCode(gen, IIf(got >= 2, buf(0) * 256 + buf(1), 0))
                SetState(gen, NET_CLOSED)
                running = False
                Exit Do
            End If
            If (meta->flags And (CURLWS_TEXT Or CURLWS_BINARY Or CURLWS_CONT)) <> 0 Then
                If Len(msg) + got > NET_MAX_MESSAGE Then
                    SetState(gen, NET_FAILED, "The server sent too much data.")
                    running = False
                    Exit Do
                End If
                If got > 0 Then msg &= BytesToString(@buf(0), got)
                '' A message is complete when this frame is read and it is the last fragment.
                If meta->bytesleft = 0 AndAlso (meta->flags And CURLWS_CONT) = 0 Then
                    If (meta->flags And CURLWS_BINARY) = 0 Then
                        If Not PushIncoming(gen, msg) Then
                            SetState(gen, NET_FAILED, "Too many messages from the server.")
                            running = False
                            Exit Do
                        End If
                    End If
                    msg = ""
                End If
            End If
            '' PING frames are answered by libcurl automatically.
        Loop
        If Not running Then Exit Do
        If Not OutgoingWaiting(gen) Then                      '' wait for data without busy-waiting
            Dim As PollFd pfd
            pfd.fd = sock
            pfd.events = POLLIN
            c_poll(@pfd, 1, 25)
        End If
    Loop
    If running Then                                           '' stopped by us: say goodbye properly
        Dim As UByte closePayload(0 To 1) = {3, 232}          '' 1000 = normal closure
        CurlSendAll(h, @closePayload(0), 2, CURLWS_CLOSE)
        SetState(gen, NET_CLOSED)
    End If
    pCleanup(h)
    FinishWorker(c)
End Sub

Private Sub StopOpenConnection(ByVal c As NetConn Ptr)
    '' The worker checks the stop flag at least every 25 ms.
End Sub

Private Sub LibraryCleanup()
    '' Not while a detached worker may still be inside libcurl (it ends by itself).
    MutexLock(NetLock)
    Dim As Integer live = NetLiveWorkers
    MutexUnlock(NetLock)
    If NetLibOk AndAlso live = 0 Then pGlobalCleanup()
End Sub

#endif

'' =====================================================================
'' Common part (main thread)
'' =====================================================================
Function Net_LibraryInfo() As String
    Net_Init()
    Return NetLibText
End Function

Function Net_Connect(ByRef url As Const String, ByRef errMsg As String) As Boolean
    errMsg = ""
    If Not Net_Init() Then
        errMsg = NetLibText
        Return False
    End If
    Dim As Boolean secure
    Dim As String host, path
    Dim As Integer port
    If Not Net_ParseUrl(url, secure, host, port, path, errMsg) Then Return False
    Net_Disconnect()
    Dim As NetConn Ptr c = New NetConn
    c->secure = secure : c->host = host : c->port = port : c->path = path
    MutexLock(NetLock)
    NetGeneration += 1
    c->generation = NetGeneration
    NetCurrent = c
    ClearQueues()
    NetStopFlag = False
    NetErrorText = ""
    NetCloseCodeValue = 0
    NetStateValue = NET_CONNECTING
    NetLiveWorkers += 1
    MutexUnlock(NetLock)
    NetThread = ThreadCreate(@WorkerThread, c, 262144)
    If NetThread = 0 Then
        MutexLock(NetLock)
        NetCurrent = 0
        NetLiveWorkers -= 1
        MutexUnlock(NetLock)
        Delete c
        SetState(NetGeneration, NET_FAILED, "Could not start the network thread.")
        errMsg = Net_Error()
        Return False
    End If
    Return True
End Function

Function Net_State() As Integer
    If NetLock = 0 Then Return NET_IDLE
    MutexLock(NetLock)
    Dim As Integer s = NetStateValue
    MutexUnlock(NetLock)
    Return s
End Function

Function Net_Error() As String
    If NetLock = 0 Then Return ""
    MutexLock(NetLock)
    Dim As String e = NetErrorText
    MutexUnlock(NetLock)
    Return e
End Function

Function Net_CloseCode() As Integer
    If NetLock = 0 Then Return 0
    MutexLock(NetLock)
    Dim As Integer c = NetCloseCodeValue
    MutexUnlock(NetLock)
    Return c
End Function

Function Net_Send(ByRef text As Const String) As Boolean
    If NetLock = 0 OrElse Len(text) = 0 Then Return False
    MutexLock(NetLock)
    If NetStateValue <> NET_OPEN OrElse OutCount >= NET_OUT_QUEUE Then
        MutexUnlock(NetLock)
        Return False
    End If
    OutQ((OutHead + OutCount) Mod NET_OUT_QUEUE) = text
    OutCount += 1
    CondBroadcast(NetWake)
    MutexUnlock(NetLock)
    Return True
End Function

Function Net_Receive(ByRef text As String) As Boolean
    If NetLock = 0 Then Return False
    MutexLock(NetLock)
    If InCount = 0 Then
        MutexUnlock(NetLock)
        Return False
    End If
    text = InQ(InHead)
    InQ(InHead) = ""
    InHead = (InHead + 1) Mod NET_IN_QUEUE
    InCount -= 1
    MutexUnlock(NetLock)
    Return True
End Function

Sub Net_Disconnect()
    If NetThread = 0 Then Exit Sub
    MutexLock(NetLock)
    Dim As Integer st = NetStateValue
    Dim As NetConn Ptr c = NetCurrent
    NetStopFlag = True
    CondBroadcast(NetWake)
    If st = NET_CONNECTING Then
        '' Still inside the library's connect: do not wait. The worker is now
        '' stale; it notices this after connecting, cleans up and ends.
        NetGeneration += 1
        NetCurrent = 0
        NetStateValue = NET_CLOSED
        MutexUnlock(NetLock)
        ThreadDetach(NetThread)
        NetThread = 0
        Exit Sub
    End If
    MutexUnlock(NetLock)
    If st = NET_OPEN AndAlso c <> 0 Then StopOpenConnection(c)
    ThreadWait(NetThread)                     '' quick: the worker stops within ~25 ms
    NetThread = 0
    MutexLock(NetLock)
    NetCurrent = 0
    If NetStateValue = NET_CONNECTING OrElse NetStateValue = NET_OPEN Then NetStateValue = NET_CLOSED
    MutexUnlock(NetLock)
    If c <> 0 Then Delete c                   '' the worker left it to us (see FinishWorker)
End Sub

Sub Net_Shutdown()
    Net_Disconnect()
    LibraryCleanup()
End Sub
