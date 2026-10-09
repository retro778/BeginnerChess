# BeginnerChess network protocol — version 1

This document describes the messages between the BeginnerChess client and a
BeginnerChess multiplayer server. It documents **what is implemented**; parts
that are still being built are listed at the end under *Planned*.

* Application version (client/server) and **protocol version** are separate.
  This document is protocol version **1**.
* Transport: WebSocket over TLS (`wss://`). The public server is
  `wss://freedomnet.tech/chess/ws`. Unencrypted `ws://` is accepted by the
  client only for `localhost` (development).

## 1. Frames and messages

* One **text frame = one JSON object** (UTF-8). Binary frames are rejected.
* Client → server messages are limited to **16 384 bytes** (the server announces
  the limit in `welcome`). A larger message closes the connection with WebSocket
  code **1009**.
* JSON nesting depth is limited to 8.
* Every message has a `type`: lower case letters, digits and `_`, 1–32 characters.
* A client **request** may carry a `request_id` (1–64 characters from
  `A–Z a–z 0–9 _ . : -`). The server copies it into the **answer**, so the client
  can match answers to requests. Use a new id for every request.
* Messages the server sends on its own (**events**) have no `request_id`.

## 2. Handshake

The first message on a new connection must be `hello`, sent within **10 seconds**.

```json
{"type": "hello", "request_id": "h1", "protocol_version": 1,
 "client_name": "BeginnerChess", "client_version": "2.0.0"}
```

| field | rules |
|-------|-------|
| `protocol_version` | whole number; must equal the server's protocol version |
| `client_name` | 1–40 characters |
| `client_version` | 1–20 characters (shown in logs only) |

Answer:

```json
{"type": "welcome", "request_id": "h1", "protocol_version": 1,
 "server_name": "BeginnerChess Server", "server_version": "2.0.0",
 "connection_id": "18fad12e26177d94",
 "limits": {"max_message_size": 16384, "heartbeat_seconds": 20.0},
 "features": {"guests": true, "registration": true, "rated_games": true}}
```

`features` tells the client which functions the operator has switched on.

Failures:

| situation | server sends | then closes with |
|-----------|--------------|------------------|
| other protocol version | `error` `incompatible_version` (text: "Your BeginnerChess version is incompatible with this multiplayer server. Please update BeginnerChess.") | **4001** |
| first message is not `hello` | `error` `hello_required` | 1008 |
| no `hello` within 10 s | `error` `hello_required` | **4002** |
| invalid `hello` | `error` `bad_message` | 1008 |

## 3. Errors

```json
{"type": "error", "request_id": "r7", "code": "unknown_type",
 "message": "Unknown request type 'xyz'."}
```

`code` is stable and meant for programs; `message` is English text for people.
`request_id` is present when the failed request had a valid one. Some errors
carry extra fields (e.g. `current_ply` for `conflict`).

| code | meaning |
|------|---------|
| `bad_json` | the frame is not valid JSON |
| `bad_message` | not an object, missing/invalid `type`, `request_id` or field |
| `unknown_type` | no such request |
| `hello_required` | the connection has not been greeted |
| `already_greeted` | a second `hello` |
| `incompatible_version` | protocol version not supported |
| `rate_limited` | too many messages (see §5) |
| `not_authenticated` | the request needs a login (guest or account) |
| `forbidden` | logged in, but not allowed |
| `not_found` | unknown game, player, challenge ... |
| `conflict` | stale or duplicate request (e.g. wrong `expected_ply`) |
| `illegal_move` | the move is not legal in the current position |
| `not_your_turn` | the other player is to move |
| `game_over` | the game has already ended (with `result`, `termination`) |
| `unavailable` | the operator has switched the function off |
| `internal_error` | a bug on the server; the request had no effect |

An error never changes server state. After an error the connection stays open,
except in the cases of §2 and §5.

## 4. Requests available to every greeted client

### `ping` → `pong`
Application-level heartbeat and clock reference.
```json
{"type": "ping", "request_id": "p1"}
{"type": "pong", "request_id": "p1", "server_time_ms": 1791496991000}
```
In addition, the server sends WebSocket protocol pings every 20 s and closes the
connection when no pong arrives within 20 s (both libraries used by the client
answer protocol pings automatically).

### `server_info` → `server_info`
```json
{"type": "server_info", "request_id": "i1"}
{"type": "server_info", "request_id": "i1", "server_version": "2.0.0",
 "protocol_version": 1, "players_online": 3,
 "features": {"guests": true, "registration": true, "rated_games": true}}
```

## 5. Limits and closing

| limit | default | on violation |
|-------|---------|--------------|
| message size | 16 KiB | close 1009 |
| messages | burst 20, then 5 per second (token bucket, per connection) | `error rate_limited` (message ignored) |
| invalid messages | 10 protocol violations per connection (bad JSON, unknown types, rate-limit hits ...) | close **4008** |
| connections | 500 in total, 8 per IP address | HTTP 503 at the handshake |
| new connections | 30 per IP address per minute | HTTP 503 at the handshake |
| login | a greeted connection must log in (guest or account) within 5 minutes | close **4011** |
| expensive requests | `register` 5 per address per hour; `challenge` 10 and `matchmaking_join` 12 per player per minute; `delete_account` 5 per address per hour | `error rate_limited` with `retry_after` (seconds) |

WebSocket close codes used by the server:

| code | meaning |
|------|---------|
| 1001 | server shutting down (preceded by an event `{"type": "server_shutdown", "message": ...}`) |
| 1008 | handshake broken |
| 1009 | message too big |
| 1013 | server full, try again later |
| 4001 | incompatible protocol version |
| 4002 | no `hello` in time |
| 4008 | too many invalid requests |
| 4009 | the same account logged in on another connection |
| 4010 | session ended by the operator (preceded by `{"type": "server_notice", "message": ...}`) |
| 4011 | no login within the time limit |

## 6. HTTP endpoints

`GET /chess/health` (same port, behind the same proxy) returns
`{"status": "ok", "protocol_version": 1, "server_version": "2.0.0"}` — for
monitoring; it contains no player or system information. Any other path
except the WebSocket path answers 404.

## 6a. Guest login and quick match

### `login_guest` → `logged_in`
```json
{"type": "login_guest", "request_id": "g1", "nickname": "Max_123"}
{"type": "logged_in", "request_id": "g1", "player": {"name": "Guest_Max_123", "kind": "guest"}}
```
* Nickname: 3–16 letters, digits or `_`; shown as `Guest_<nickname>`
  (account names can never start with "Guest", so guests cannot imitate
  registered players). The server gives each guest a random internal id; the
  name is never used as an identity.
* Errors: `bad_message` (invalid name), `conflict` (name in use by someone online,
  case-insensitive; or already logged in), `unavailable` (guests switched off).

### `matchmaking_join` → `matchmaking_waiting` or `matchmaking_found`
```json
{"type": "matchmaking_join", "request_id": "q1",
 "time_control": {"initial_seconds": 600, "increment_seconds": 0}, "rated": false}
```
* Needs a login. Time controls as in §7.7. `rated: true` needs an account
  (`forbidden` for guests; `unavailable` if switched off).
* If a player with the same time control (and rated flag) is waiting, both get
  `matchmaking_found` and then `game_started` (colours at random); otherwise the
  answer is `matchmaking_waiting`.
* `conflict` if already waiting or already playing.

### `matchmaking_cancel` → `ok`
Leaves the queue (`conflict` if not waiting). Disconnecting also leaves it.

### `lobby_subscribe` → `lobby`, then `lobby` events
```json
{"type": "lobby_subscribe", "request_id": "l1"}
{"type": "lobby", "request_id": "l1", "total": 3,
 "players": [{"name": "Guest_Max", "kind": "guest", "status": "available"},
             {"name": "Guest_Ann", "kind": "guest", "status": "waiting"},
             {"name": "Guest_Leo", "kind": "guest", "status": "playing"}]}
```
* Needs a login. `status`: `available`, `waiting` (in quick match) or `playing`.
  Accounts will add `rating`. At most 100 players are listed (`total` counts all).
* After subscribing, the client receives `lobby` events (same format, no
  `request_id`) whenever the list changes; changes within half a second are
  combined into one update. `lobby_unsubscribe` → `ok` stops them; they also stop
  when the connection closes.
* Nothing private is sent (no ids, no addresses).

## 6b. Accounts

All names are case-insensitive for logging in and for uniqueness.
User names: 3–16 letters, digits or `_`, not starting with "Guest". Passwords:
8–128 characters, different from the user name.

| request | fields | answer |
|---------|--------|--------|
| `register` | `username`, `password` | `logged_in` (with `session_token`) · errors `bad_message`, `conflict` (name taken), `unavailable` |
| `login` | `username`, `password` | `logged_in` (with `session_token`) · `forbidden` "Wrong user name or password." (same text whether or not the name exists), `forbidden` suspended, `rate_limited` |
| `resume` | `session_token` | `logged_in` · `not_authenticated` (expired/revoked: log in again) |
| `logout` | – | `logged_out`; the session is deleted on the server |
| `delete_account` | `password` | `account_deleted` · `forbidden` (wrong password, or a guest) · `conflict` (in a game) |
| `profile` | `username` (optional; own profile without it) | `profile` |
| `history` | `offset` (default 0), `limit` (1–50, default 20) | `history` (own finished games, newest first; accounts only) |
| `game_record` | `game_id` | `game_record` (moves, PGN, result ...) of a finished game; a running game gives `not_found` |

```json
{"type": "logged_in", "request_id": "a1",
 "player": {"name": "Maya_7", "kind": "account", "rating": 1200, "provisional": true},
 "stats": {"games": 4, "wins": 2, "losses": 1, "draws": 1},
 "session_token": "kQ3..."}
```

* The session token is a secret: whoever has it is logged in. The server stores
  only its SHA-256 hash. It stays valid for 30 days after its last use
  (configurable), until `logout`, or until the account is deleted. The client
  keeps it only if the player chose "remember me" (see `docs/PRIVACY.md`).
* Only one connection per account: a new login closes the old connection after
  an event `{"type": "session_replaced", "message": ...}` (close code **4009**).
* Failed logins are limited: 5 per user name and 20 per address within 15
  minutes (`rate_limited`); failed `resume` attempts count per address.
* Stored are only games with at least one account; games between two guests
  are never stored (and so never appear anywhere).
* Profile (no private data): `name`, `rating`, `provisional`, `rated_games`,
  `games`, `wins`, `losses`, `draws`, `member_since` (`"2026-10"`) and
  `recent_games` (10 game summaries). Game summary: `game_id`, `white`, `black`,
  `color` and `opponent` (from the profile owner's view), `outcome`
  (`win`/`loss`/`draw`/`aborted`), `result`, `termination`, `rated`,
  `time_control`, `date`.
* Finished games are public records (like a tournament bulletin): any logged-in
  player can request them by id.

## 6c. Challenges, rated games, leaderboard

### Direct challenges
| request | fields | answer / events |
|---------|--------|-----------------|
| `challenge` | `opponent` (name), `time_control`, `rated` | `challenge_sent` `{challenge}`; the opponent gets `challenge_received` `{challenge}` |
| `challenge_accept` | `challenge_id` | `ok`; the challenger gets `challenge_accepted`; both get `game_started` |
| `challenge_decline` | `challenge_id` | `ok`; the challenger gets `challenge_declined` |
| `challenge_cancel` | `challenge_id` | `ok`; the opponent gets `challenge_cancelled` `{"reason": "cancelled"}` |

`challenge` object: `challenge_id`, `from`, `to` (public player info),
`time_control`, `rated`, `expires_seconds` (60). Rules: not yourself; the
opponent must be online and not playing (`not_found` / `conflict`); one open
challenge per opponent, at most 3 sent and 10 received; rated challenges only
between two accounts (`forbidden`). After 60 seconds both get
`challenge_expired`. When a player starts a game or leaves, their open
challenges end with `challenge_cancelled` and `reason` `busy` or `left`.

### Rated games and ratings
* `matchmaking_join` and `challenge` accept `"rated": true` (two accounts only).
  Rated quick match pairs players whose ratings differ by at most 200 points;
  the accepted difference grows by 50 points for every 5 seconds of waiting
  (up to 1000).
* After a rated game both players get
  `{"type": "rating_update", "game_id": ..., "white": {"before": 1200, "after": 1180, "provisional": true}, "black": {...}}`.
* Elo: start 1200; `E = 1/(1+10^((Ropp-R)/400))`; `R' = round(R + K(S-E))`;
  K = 40 for the first 20 rated games (provisional), then 20; minimum 100.
  Only finished rated games count (also when won by abandonment); aborted games
  never. Each game is rated once. Online ratings are separate from the offline
  "player rating" of Beginner Chess.

### `leaderboard` → `leaderboard`
`{"offset": 0, "limit": 20}` (limit 1–50) →
`{"total": 57, "offset": 0, "players": [{"rank": 1, "name": "Maya_7", "rating": 1450, "games": 31, "provisional": false}, ...]}`.
Accounts with at least one rated game; guests never appear.

## 6d. Connection loss, reconnecting, server restart

* When a player's connection drops during a game, the clocks keep running and
  the opponent gets `{"type": "opponent_disconnected", "game_id", "grace_seconds": 60}`.
* The player comes back with `resume` (accounts: their session token; guests:
  the `session_token` from `login_guest`, kept in memory by the server only while
  the guest's game runs). After `logged_in` the server sends
  `{"type": "game_resumed", "game": {snapshot}}`; the opponent gets
  `opponent_reconnected`. The client reconnects automatically (pauses of 1, 2, 4,
  8, 8 ... seconds, for up to 90 seconds).
* A guest's name stays reserved while their game runs.
* After `grace_seconds` the player who is still there may send
  `{"type": "claim_abandonment", "game_id", "outcome": "win"|"draw"}` →
  `game_over` with termination `abandoned`. Too early: `conflict` with
  `seconds_left`; opponent connected: `conflict`.
* Snapshots contain `"away": {"w": seconds}` for a disconnected side.
* **Server restart:** running games are saved after every move. After a restart,
  games between two accounts are restored with the clock times of the last move
  (the downtime is not charged; the side to move's clock starts at the restart)
  and both players count as disconnected until they come back. Games with a guest,
  and games before both first moves, end as `aborted` with termination
  `server_restart` (no result, no rating change). No win is ever awarded because
  of a restart.

## 7. Games

All game requests need a logged-in player (guest or account; otherwise
`not_authenticated`) and name the game with `game_id`. A game id that does not
exist and a game the player does not take part in both give `not_found`.
The server is the only authority: the client shows what the server confirms.

Squares and moves use **UCI** notation: `e2e4`, `e1g1` (castling = the king's
move), `e7e8q` (promotion: `q r b n`). The server adds the SAN (`e4`, `O-O`,
`e8=Q+`) for display.

### 7.1 Game start — event `game_started`
```json
{"type": "game_started", "game": { ...snapshot... }}
```
**Snapshot** (also in `game_state`):

| field | meaning |
|-------|---------|
| `game_id` | random id |
| `seq` | state number: increases with every change (move, draw offer, end) |
| `white`, `black` | `{"name": "Guest_Max", "kind": "guest"}`; accounts add `rating`, `provisional` |
| `your_color` | `"w"` or `"b"` |
| `rated` | true/false |
| `time_control` | `{"initial_seconds": 600, "increment_seconds": 0}` |
| `initial_fen`, `moves` (UCI), `san` | the complete game |
| `fen`, `ply`, `turn`, `in_check` | current position (`ply` = number of moves played) |
| `status` | `active`, `finished` or `aborted` |
| `result`, `termination` | see §7.6 (null while active) |
| `draw_offer` | `"w"`, `"b"` or null |
| `can_claim_draw` | true if the side to move may claim threefold repetition / 50 moves |
| `clock` | `{"white_ms", "black_ms", "running": "w"/"b"/null, "first_move_ms": n/null}` |

### 7.2 `move`
```json
{"type": "move", "request_id": "m5", "game_id": "...", "move": "g1f3",
 "expected_ply": 4, "claim_draw": false}
```
* `expected_ply` = the `ply` the client's board shows (number of moves already
  played). If the game has moved on: `conflict` with `current_ply` → reload with
  `game_state`.
* Not this player's turn: `not_your_turn`. Illegal: `illegal_move` (no
  violation counted). Game over: `game_over` with `result`/`termination`.
* **Retries are safe:** sending the same move again with the same
  `expected_ply` (e.g. after a timeout) returns `move_accepted` with
  `"duplicate": true`; the move is not played twice.
* `claim_draw: true` claims a threefold repetition / fifty-move draw that this
  move creates (FIDE: the claim is made with the move).

Accepted — the mover gets this as the answer (with its `request_id`), the
opponent gets the same message as an event:
```json
{"type": "move_accepted", "game_id": "...", "seq": 7, "ply": 5, "move": "g1f3",
 "san": "Nf3", "fen": "...", "turn": "b", "in_check": false, "draw_offer": null,
 "can_claim_draw": false,
 "clock": {"white_ms": 597120, "black_ms": 598800, "running": "b", "first_move_ms": null}}
```

### 7.3 `game_state` → `game_state`
`{"type": "game_state", "request_id": "s1", "game_id": "..."}` → `{"type":
"game_state", "game": {snapshot}}` — for reloading after a `conflict`, a gap
in `seq`, or a reconnect.

### 7.4 Draws
* `offer_draw` → answer `ok`; the opponent gets `{"type": "draw_offered",
  "by": "white"}`. If the opponent had already offered, this is an agreement
  (game over). One offer per player per move; an offer is cleared when the
  opponent makes a move instead of answering.
* `accept_draw` → `game_over` (agreement). `decline_draw` → `ok`; the offering
  player gets `draw_declined`. Both need an open offer from the opponent
  (otherwise `conflict`).
* `claim_draw` → `game_over` if the **side to move** can claim threefold
  repetition or the fifty-move rule; otherwise `conflict` / `not_your_turn`.
* Automatic (no claim): checkmate, stalemate, insufficient material, fivefold
  repetition, 75-move rule (a mate on that move counts as mate).

### 7.5 `resign`, `abort`
* `resign` (any time, also when it is not your turn) → loss. Before both sides
  have made a move it is treated as `abort`.
* `abort` → only before both sides have moved; no result, no rating change.

### 7.6 Game over — event `game_over`
```json
{"type": "game_over", "game_id": "...", "seq": 12, "status": "finished",
 "result": "1-0", "termination": "resignation", "clock": {...}, "pgn": "[Event ..."}
```
Sent to both players (the player whose request ended the game gets it as the
answer, with the `request_id`).

| `termination` | `result` |
|---------------|----------|
| `checkmate` | `1-0` / `0-1` |
| `resignation` | `1-0` / `0-1` |
| `timeout` | `1-0` / `0-1` |
| `timeout_vs_insufficient_material` | `1/2-1/2` (the winner could not have checkmated) |
| `stalemate`, `insufficient_material`, `fivefold_repetition`, `seventyfive_moves` | `1/2-1/2` (automatic) |
| `threefold_repetition`, `fifty_moves` | `1/2-1/2` (claimed) |
| `agreement` | `1/2-1/2` |
| `abandoned` | `1-0` / `0-1` (claimed win) or `1/2-1/2` (claimed draw) |
| `first_move_timeout`, `aborted_by_player`, `server_restart` | null, `status: "aborted"` |

### 7.7 Clocks
* Time controls: 3, 5, 10, 15 or 30 minutes; increment 0, 2, 5 or 10 seconds.
* Each side has **30 seconds for its first move** (`first_move_ms`); otherwise the
  game is aborted.
* From then on the clock of the side to move runs, measured by the server with a
  monotonic clock from the moment the opponent's move was accepted. After each
  move the increment is added. Clients may count down between messages for a
  smooth display, but the server's numbers are authoritative.
* Network delay is not compensated in protocol version 1.
* Out of time: loss — or a draw if the opponent has insufficient mating
  material (lone king; king + one knight against king and queens only; king and
  bishops all on one colour with no knights or pawns on the board).

## 8. Planned (not implemented yet)

Nothing - protocol version 1 is complete. Operator commands are not part of the
player protocol (Unix socket, see `docs/SERVER_OPERATIONS.md`).
