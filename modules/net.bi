'' =====================================================================
'' BeginnerChess - net.bi
'' Secure WebSocket connection to a BeginnerChess multiplayer server.
''
'' Libraries (loaded at run time, nothing to link):
''   * Linux:   libcurl >= 8.11 (libcurl.so.4) - WebSocket API, OpenSSL/GnuTLS
''   * Windows: WinHTTP (winhttp.dll, part of Windows 8 and later)
'' TLS certificates are always verified (by libcurl with the system CA store,
'' by Windows with its certificate store). wss:// is required, except ws://
'' to localhost for development. BEGINNERCHESS_CAFILE=<file> (Linux) adds a
'' CA file to trust - used by the automated tests with their own test CA.
''
'' Concurrency: the connection is run by a worker thread (Windows: plus a
'' sender thread). The main program only calls the functions below; they
'' exchange complete text messages through two mutex-protected queues and
'' never block on the network.
'' =====================================================================
#pragma once

Enum NetState
    NET_IDLE = 0          '' never connected
    NET_CONNECTING        '' TCP, TLS and WebSocket handshake in progress
    NET_OPEN              '' messages can be exchanged
    NET_CLOSED            '' closed normally (by us or the server; see Net_CloseCode)
    NET_FAILED            '' could not connect, or the connection broke (see Net_Error)
End Enum

Const NET_MAX_MESSAGE = 1048576          '' largest message accepted from the server
Const NET_IN_QUEUE = 512                 '' messages waiting for the program
Const NET_OUT_QUEUE = 128                '' messages waiting to be sent

'' Loads the network library once. False if it is missing or too old;
'' Net_LibraryInfo then explains why. Safe to call often.
Declare Function Net_Init() As Boolean
Declare Function Net_LibraryInfo() As String

'' Splits and checks a server address. Only wss://, or ws:// to localhost.
Declare Function Net_ParseUrl(ByRef url As Const String, ByRef secure As Boolean, ByRef host As String, _
                              ByRef port As Integer, ByRef path As String, ByRef errMsg As String) As Boolean

'' Starts connecting (returns at once). False if the address is invalid or
'' the library is missing (errMsg). A previous connection is closed first.
Declare Function Net_Connect(ByRef url As Const String, ByRef errMsg As String) As Boolean
Declare Function Net_State() As Integer
Declare Function Net_Error() As String          '' friendly reason for NET_FAILED
Declare Function Net_CloseCode() As Integer      '' WebSocket close code from the server (0 = none)

'' Queues one text message. False if not connected or the queue is full.
Declare Function Net_Send(ByRef text As Const String) As Boolean
'' Takes the next received message. False if none is waiting.
Declare Function Net_Receive(ByRef text As String) As Boolean

'' Closes the connection (sends a WebSocket close, stops the worker).
Declare Sub Net_Disconnect()
'' At program end.
Declare Sub Net_Shutdown()
