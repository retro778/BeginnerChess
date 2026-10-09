'' =====================================================================
'' BeginnerChess - online.bi
'' Client side of the BeginnerChess multiplayer protocol (docs/PROTOCOL.md).
''
'' Runs entirely in the main thread: Online_Update (once per frame) takes
'' the messages that net.bas has received, updates the state below and
'' produces events for the screens (Online_NextEvent). Requests are sent
'' with the helper functions; answers come back as events with the same
'' request id. The server is authoritative: the local game copy is only
'' changed by server messages.
'' =====================================================================
#pragma once
#include once "json.bi"
#include once "net.bi"

Const ONLINE_PROTOCOL_VERSION = 1
Const ONLINE_DEFAULT_SERVER = "wss://freedomnet.tech/chess/ws"

Enum OnlineStatus
    OL_OFFLINE = 0        '' not connected (or connection closed)
    OL_CONNECTING         '' network connection being set up
    OL_HANDSHAKE          '' connected, waiting for "welcome"
    OL_READY              '' greeted: requests can be sent
    OL_LOST               '' connection failed or broke (see Online_StatusText)
    OL_RECONNECTING       '' lost during a game: trying to come back automatically
End Enum

Type OnlineLobbyEntry
    playerName As String
    kind       As String          '' "guest" or "account"
    rating     As Integer         '' -1 = none
    status     As String          '' "available", "waiting", "playing"
End Type

Type OnlineGameSummary
    gameId      As String
    whiteName   As String
    blackName   As String
    opponent    As String
    colour      As String         '' "w" / "b" (of the player the list belongs to)
    outcome     As String         '' "win", "loss", "draw", "aborted"
    result      As String
    termination As String
    rated       As Boolean
    minutes     As Integer
    increment   As Integer
    dateText    As String         '' "2026-10-08"
End Type

Type OnlineProfile
    valid       As Boolean
    playerName  As String
    rating      As Integer
    provisional As Boolean
    ratedGames  As Integer
    games       As Integer
    wins        As Integer
    losses      As Integer
    draws       As Integer
    memberSince As String         '' "2026-10"
    recentCount As Integer
    recent(Any) As OnlineGameSummary
End Type

Type OnlineEvent
    kind        As String     '' message type ("welcome", "move_accepted", "error", ...) or
                              '' "request_timeout", "connection_lost", "connection_closed"
    text        As String     '' the complete JSON message (parse with Json_Parse if needed)
    requestId   As String     '' request this answers ("" for server events)
    requestType As String     '' type of that request ("move", "login_guest", ...)
    code        As String     '' error code for kind = "error"
    message     As String     '' human-readable text (errors, connection problems)
End Type

'' Local copy of the current online game (from server messages only).
Type OnlineGame
    active      As Boolean      '' a game is shown (also after it ended)
    gameId      As String
    seq         As Integer
    myColor     As String       '' "w" / "b"
    whiteName   As String
    blackName   As String
    whiteRating As Integer      '' -1 = unrated (guest)
    blackRating As Integer
    rated       As Boolean
    initialSec  As Integer
    incrementSec As Integer
    ply         As Integer
    moves(Any)  As String       '' UCI, index 0 = first move
    sans(Any)   As String
    fen         As String
    turn        As String
    inCheck     As Boolean
    status      As String       '' "active", "finished", "aborted"
    result      As String
    termination As String
    drawOffer   As String       '' "", "w", "b"
    canClaim    As Boolean
    whiteMs     As LongInt
    blackMs     As LongInt
    running     As String       '' "w", "b" or ""
    firstMoveMs As LongInt      '' -1 if not applicable
    clockAt     As Double       '' Timer when the clock values arrived
    pgn         As String       '' after the game
    needResync  As Boolean      '' a gap was detected: a game_state request was sent
    opponentAway As Boolean     '' the opponent's connection is lost
    awaySince   As Double       '' Timer when it was lost (counts towards the grace period)
    graceSec    As Integer      '' after this the opponent can be claimed as gone
    myBefore    As Integer      '' rating change of a rated game (-1 = none yet)
    myAfter     As Integer
End Type

Type OnlineChallenge
    challengeId As String
    playerName  As String         '' the other player
    rating      As Integer        '' -1 = guest
    minutes     As Integer
    increment   As Integer
    rated       As Boolean
    received    As Double         '' Timer
End Type

Type OnlineLeaderEntry
    rank        As Integer
    playerName  As String
    rating      As Integer
    games       As Integer
    provisional As Boolean
End Type

'' ---- Connection ------------------------------------------------------
Declare Function Online_Connect(ByRef url As Const String, ByRef errMsg As String) As Boolean
Declare Sub Online_Disconnect()
Declare Function Online_Status() As Integer
Declare Function Online_StatusText() As String           '' for the screens ("Connected to ...")
Declare Function Online_ServerHost() As String
Declare Function Online_Feature(ByRef featureName As Const String) As Boolean
'' Must be called regularly (each frame); now = Timer.
Declare Sub Online_Update(ByVal now As Double)
Declare Function Online_NextEvent(ByRef ev As OnlineEvent) As Boolean

'' ---- Requests (return the request id, "" if not connected) -----------
Declare Function Online_LoginGuest(ByRef nickname As Const String) As String
Declare Function Online_QuickMatch(ByVal minutes As Integer, ByVal incrementSec As Integer, ByVal rated As Boolean) As String
Declare Function Online_CancelMatch() As String
Declare Function Online_SendMove(ByRef uci As Const String, ByVal claimDraw As Boolean = False) As String
Declare Function Online_Resign() As String
Declare Function Online_OfferDraw() As String
Declare Function Online_AcceptDraw() As String
Declare Function Online_DeclineDraw() As String
Declare Function Online_ClaimDraw() As String
Declare Function Online_Abort() As String
Declare Function Online_RequestGameState() As String
Declare Function Online_Ping() As String

'' ---- Current game ----------------------------------------------------
Declare Function Online_Game() As OnlineGame Ptr
'' Remaining time (ms) of a side, counted down locally since the last update.
Declare Function Online_ClockMs(ByRef colour As Const String, ByVal now As Double) As LongInt
Declare Sub Online_ClearGame()

'' For tests: how many requests are waiting for an answer.
Declare Function Online_PendingCount() As Integer
'' For screenshots/tests: handle a server message as if it had arrived.
Declare Sub Online_DebugInject(ByRef text As Const String, ByVal markReady As Boolean = True)

'' ---- Player and lobby ------------------------------------------------
Declare Function Online_LoggedIn() As Boolean
Declare Function Online_MyName() As String
Declare Function Online_Waiting() As Boolean          '' in the quick-match queue
Declare Function Online_LobbySubscribe() As String
Declare Function Online_LobbyUnsubscribe() As String
Declare Function Online_LobbyCount() As Integer       '' entries listed
Declare Function Online_LobbyTotal() As Integer       '' players online
Declare Function Online_LobbyEntry(ByVal index As Integer) As OnlineLobbyEntry Ptr

'' ---- Accounts --------------------------------------------------------
Declare Function Online_Register(ByRef username As Const String, ByRef password As Const String) As String
Declare Function Online_Login(ByRef username As Const String, ByRef password As Const String) As String
Declare Function Online_Resume(ByRef token As Const String) As String
Declare Function Online_Logout() As String
Declare Function Online_DeleteAccount(ByRef password As Const String) As String
Declare Function Online_MyKind() As String              '' "guest", "account" or ""
Declare Function Online_MyRating() As Integer           '' -1 for guests
Declare Function Online_MyProvisional() As Boolean
Declare Function Online_SessionToken() As String        '' of the current login (accounts)
'' Profile ("" = own) and own match history (20 per page).
Declare Function Online_RequestProfile(ByRef username As Const String) As String
Declare Function Online_RequestHistory(ByVal offset As Integer) As String
Declare Function Online_RequestGameRecord(ByRef gameId As Const String) As String
Declare Function Online_Profile() As OnlineProfile Ptr
Declare Function Online_HistoryCount() As Integer
Declare Function Online_HistoryOffset() As Integer
Declare Function Online_HistoryEntry(ByVal index As Integer) As OnlineGameSummary Ptr

'' ---- Challenges, leaderboard, reconnection -------------------------------
Declare Function Online_Challenge(ByRef opponent As Const String, ByVal minutes As Integer, _
                                  ByVal incrementSec As Integer, ByVal rated As Boolean) As String
Declare Function Online_ChallengeAccept(ByRef challengeId As Const String) As String
Declare Function Online_ChallengeDecline(ByRef challengeId As Const String) As String
Declare Function Online_ChallengeCancel(ByRef challengeId As Const String) As String
'' Incoming challenges (oldest first) and our own open challenge (if any).
Declare Function Online_IncomingCount() As Integer
Declare Function Online_Incoming(ByVal index As Integer) As OnlineChallenge Ptr
Declare Function Online_Outgoing() As OnlineChallenge Ptr        '' challengeId = "" if none
Declare Function Online_ClaimAbandonment(ByVal win As Boolean) As String
Declare Function Online_RequestLeaderboard(ByVal offset As Integer) As String
Declare Function Online_LeaderCount() As Integer
Declare Function Online_LeaderTotal() As Integer
Declare Function Online_LeaderOffset() As Integer
Declare Function Online_LeaderEntry(ByVal index As Integer) As OnlineLeaderEntry Ptr
'' True while the client is coming back to a running game after a connection loss.
Declare Function Online_Reconnecting() As Boolean
