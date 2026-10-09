# BeginnerChess 2.0.0 — Online multiplayer: development plan

Status: **Phases 1–10 complete (2026-10-09)** — final report: `RELEASE_REPORT_2.0.0.md`. The server runs at `wss://freedomnet.tech/chess/ws`; the phase-10 server fixes were deployed the same day. The owner tested the Windows build (tests, package, online play): **2.0.0 is complete on Linux and Windows.**
This document records what was found, the decisions taken and why, and the
plan for the remaining phases. It is updated as phases are completed.

## 1. Baseline (before any 2.0 change)

* Client: 1.0.0, ~16 000 lines of FreeBASIC (`beginnerchess.bas` + `modules/`),
  immediate-mode GUI on fbgfx, engine in a worker thread (mutex + polling from
  the main loop), BASS and SQLite loaded at run time with `DyLibLoad`.
* Linux 64-bit build: **0 warnings**; tests: 10 programs, **1 887 checks, 0
  failures** (`./build.sh test`).
* Windows 32-bit: built and run by the owner on Windows (no Windows toolchain
  here); a 32-bit-only colour bug was fixed after the 1.0 release.
* Reusable pieces for online play: `rules.bas` (legal moves, FEN, draw rules),
  `notation.bas` (SAN/UCI), `board.bas` + `boardctl.bas` (interactive board),
  `play.bas` (game screen layout), the game viewer (`Viewer_StartPgn`) for
  match history, `pgn.bas`, `audio.bas` (sounds), `gui.bas` (buttons, dialogs,
  text input, toasts).

## 2. Environment findings

| Item | Finding |
|------|---------|
| Python | 3.13.5 with `venv`, `sqlite3` 3.46.1, OpenSSL 3.5 |
| Server packages | `websockets` 17.2 (BSD-3), `argon2-cffi` 25.1 (MIT), `pytest` 9.1 (MIT) install from PyPI |
| libcurl (Linux) | 8.14.1 with `ws`/`wss`; the WebSocket API (`curl_ws_send/recv`) is stable since 8.11 |
| libcurl (Windows 32-bit) | **curl.se no longer offers 32-bit Windows builds** (only x64/ARM64, checked 2026-10-08); no mingw cross-compiler here |
| WinHTTP | part of every Windows since 8 (32- and 64-bit), has a native WebSocket API, uses the Windows TLS stack and certificate store |
| FreeBASIC headers | `curl.bi` is too old for WebSockets; no `winhttp.bi` → own declarations, loaded at run time (as for BASS/SQLite) |
| freedomnet.tech | DNS A record set; **nothing answers on TCP 443 or 80** from here (connection timed out) → a reverse proxy + certificate must be set up in the deployment phase |
| VPS access | none from this machine; deployment needs the owner's approval and access (see §8) |

## 3. Decisions

### 3.1 Chess rules on the server: own MIT implementation (not python-chess)
python-chess is **GPL-3.0**. Using it would make the server a GPL work; it
could still be published, but not as "MIT throughout", and the obligation would
need explaining to every self-hoster. A permissive alternative of the needed
quality does not exist, so the server gets its **own rules module in Python,
MIT**, a port of the client's already verified rules (0x88 board, legal move
generation, FEN, SAN/UCI, castling, en passant, promotion, check/mate/stalemate,
insufficient material, 3-/5-fold repetition, 50/75-move rules). Correctness is
proven the same way as the client's: **perft** against the standard reference
counts (start position to depth 5, Kiwipete, the other standard positions) plus
unit tests for every special rule, and a cross-check that client and server
generate the same legal moves for thousands of positions.

### 3.2 Client networking: one module, two proven OS libraries
`modules/net.bas` offers one small interface (connect, send text, receive text,
close, status). Backends:

* **Linux: libcurl ≥ 8.11** (`libcurl.so.4`, standard package) — `CONNECT_ONLY=2`
  WebSocket mode, `curl_ws_send` / `curl_ws_recv`; TLS verification with the
  system CA store (`CURLOPT_SSL_VERIFYPEER/VERIFYHOST` stay on).
* **Windows: WinHTTP** (`winhttp.dll`, part of Windows) — `WinHttpOpen/Connect/
  OpenRequest`, `WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET`,
  `WinHttpWebSocketCompleteUpgrade/Send/Receive/Close`; certificates are verified
  by Windows (default behaviour, never switched off). No extra DLL to ship.

No home-made WebSocket framing, no custom cryptography. Both libraries are loaded
at run time: if they are missing, *Play Online* explains why and every offline
feature keeps working.

`ws://` (no TLS) is accepted **only** for `localhost`/`127.0.0.1` (developer
tests); every other address must be `wss://`.

### 3.3 Concurrency in the client
A network **worker thread** (like the engine thread) owns the connection: it
reads frames, answers protocol pings, and moves complete text messages into a
**mutex-protected incoming queue**; the main loop sends through a mutex-protected
**outgoing queue**. The GUI is only touched by the main loop, which drains the
incoming queue once per frame and updates the screens. Queues have fixed maximum
sizes (back-pressure: the connection is closed with an error rather than growing
without limit).

### 3.4 JSON in FreeBASIC
A small MIT JSON module (`modules/json.bas`): parse into a tree with depth/size
limits, typed getters, and a serializer with correct string escaping. Unit-tested
with valid, malformed, deeply nested and oversized input.

### 3.5 Server stack
Python 3 + asyncio + `websockets` (one process, one event loop), SQLite through a
single writer connection used via `asyncio.to_thread` (no long blocking in the
loop), WAL mode, foreign keys, migrations table. `argon2-cffi` (Argon2id) for
passwords. Session tokens: 256-bit random, only their SHA-256 stored. systemd
service under a dedicated user; Nginx (or the existing proxy, if one is found)
terminates TLS and forwards `/chess/ws` to `127.0.0.1:8765`. Administration: a
CLI talking to the running server over a **Unix socket** protected by file
permissions (no admin web site, nothing extra exposed).

### 3.6 Game policies (to be documented in the protocol and user guide)
* **Clocks:** server-authoritative, monotonic time. Each side must make its
  **first move within 30 s** or the game is *aborted* (no result, no rating).
  A side's clock runs from the moment its opponent's move is accepted; Fischer
  increment after each move. Time controls 3/5/10/15/30 min, increments 0/2/5/10 s.
* **Timeout:** loss, except a **draw** if the opponent cannot possibly checkmate
  (FIDE 6.9).
* **Disconnection:** clocks keep running. After a configurable grace period
  (default 60 s) the opponent may *claim the win* or *call it a draw*; the game
  continues normally if the player returns first.
* **Server restart:** games are saved after every move. On restart they are
  restored with the remaining clock times at the last saved move (downtime is not
  charged) and wait for both players; the disconnection rules then apply. No win
  is ever awarded automatically because of a restart.
* **Draws:** offers are cleared when the offering side's opponent moves; claims
  (threefold, fifty-move) are checked by the server; fivefold/75-move automatic.
* **Ratings:** Elo, start 1200, K = 40 for the first 20 rated games
  (provisional, shown as "1200?"), then K = 20; one rating for all time controls
  in 2.0; rated games only between two registered accounts. Kept completely
  separate from the offline "player rating".
* **Guests:** nickname 3–16 characters (letters, digits, `_`), shown as
  `Guest_<name>`; registered names may not start with `Guest`, so guests can never
  look like accounts. Each guest session has a random internal id. Casual games
  only.
* **Fair play:** in every online game the client disables hints, threats,
  take-backs, analysis and engine moves. The documentation states plainly that
  this cannot stop someone from using a separate engine.

### 3.7 Credentials on the client
The password is never stored. "Remember me" (off by default) stores the session
token: on **Windows encrypted with DPAPI** (`CryptProtectData`, bound to the
Windows user); on **Linux** in `~/.beginnerchess/online.token` with permissions
`0600` (readable only by the user). Logging out deletes it and revokes the
session on the server. Documented: there is no e-mail account recovery.

## 4. Protocol (summary; full document `docs/PROTOCOL.md` in Phase 2)
JSON text frames, `protocol_version` 1, client→server messages ≤ 16 KiB.
Every request carries a `request_id`; the server answers with the same id
(`ok`/specific reply or `error` with a stable `code`). Game state carries a `ply`
number: a move must name the `expected_ply`; stale or repeated moves are rejected
(a retry of an already-accepted move gets the current state, not a second move).
Snapshots (`game_state`) contain FEN, the move list (UCI + SAN), clocks, players,
status — sent at game start, after reconnecting, and on request.

## 5. Phases (as in the specification) and what "done" means

| Phase | Content | Done when |
|------|---------|-----------|
| 1 | Inspection, plan | **done**: this document; baseline recorded; VPS inspected |
| 2 | Server foundation: config, WebSocket transport, protocol, hello/version, limits | **done**: 36 pytest tests; `docs/PROTOCOL.md` |
| 3 | Authoritative chess: rules (perft), sessions, moves, clocks, results | **done**: perft (7 reference positions) + 600-position cross-check with the client, rule tests, 23 game tests over WebSocket incl. random complete games |
| 4 | FreeBASIC networking: json, net (libcurl/WinHTTP), worker thread, queues | **done (Linux)**: `tests/test_online` plays a full game against the local server over TLS with a test CA; untrusted / wrong-host certificates refused (also expired/self-signed/wrong-host at badssl.com); cancel-while-connecting never blocks; -exx clean; Windows-target C: 0 warnings and a 32-bit type check. **Windows run pending** (`build.bat test`, `tests\online_check.bat`). Guest login + quick match on the server done early. |
| 5 | First playable: *Play Online* menu, guest login, lobby, quick match, online game screen | **done (Linux)**: two real BeginnerChess windows played complete games on a local server (checkmate, draw by agreement, resignation, cancel), review and PGN after the game, live lobby list; server stop shows the reason and lets the player leave. Lobby list with combined updates on the server (+3 tests). **Windows run pending.** |
| 6 | Accounts: register/login/sessions, profiles, match history (+ replay in the viewer) | **done**: SQLite with migrations, Argon2id (bounded pool), hashed session tokens, throttling, one session per account, profiles/history/game records, deletion with "Deleted player"; client: masked password dialogs, remember-me (DPAPI / 0600 file), auto-login, profile screen with replay; 24 new server tests + token-store test; real two-window test of every flow. Found and fixed: lost keys when typing fast (key queue), one Enter used by two dialogs. |
| 7 | Challenges, clocks UI, rated games, Elo, leaderboard, reconnection, recovery | **done**: 13 new server tests (Elo, challenges, rated matching, reconnect, guests, abandonment, restart recovery, schema upgrade); real two-window test: rated challenge game with rating change, leaderboard, server restart mid-game with automatic reconnection, abandonment claim. |
| 8 | Security & reliability: rate limits, connection limits, login throttling, logging, backups, admin CLI, load test | **done**: new limits (connection rate, login timeout, per-request limits, session cap), admin Unix socket + CLI (status, suspend, kick, feature switches, backup, integrity), online/offline verified backups, backup script, 15 security/admin tests (182 server tests), load test 200/500/1000 players with 0 errors (results in SERVER_OPERATIONS.md); docs SECURITY.md, SERVER_OPERATIONS.md. Found: the WebSocket library logs message contents (passwords) at DEBUG - now pinned to WARNING and tested. |
| 9 | VPS deployment — **only with the owner's approval** | **done** (2026-10-09, approved without Let's Encrypt e-mail): nginx TLS proxy + Let's Encrypt, hardened systemd service, backup timer, ufw +80/443 only; existing services and firewall rules verified unchanged; public health check, 404 for everything else, port 8765 closed from outside; a complete game over the public WSS endpoint with the real certificate (23/23); VPS load test 200/500/1000 players, 0 errors |
| 10 | Final validation, docs, release 2.0.0 | **done**: CM_VERSION 2.0.0; all client suites + 184 server tests; 32-bit Windows C check of all 52 sources; offline regression (all screens, no-libcurl run); two real GUI windows played over the public server; fixes: guest-only games no longer stored (migration 3), running games hidden from history/records, lock-safe test DB access, lobby name fitting; docs ONLINE_GUIDE.md, README, USER_GUIDE, RELEASE_REPORT_2.0.0.md; packages incl. server package |

Windows: every phase keeps the code 32-bit clean (generated 32-bit C without
warnings); the owner runs `build.bat test` on Windows at the end of phases 4, 5
and 10. Windows results are reported only after the owner has run them.

## 6. Files (planned)
* Client: `modules/json.bi/.bas`, `modules/net.bi/.bas`, `modules/online.bi/.bas`
  (protocol client, state), `modules/onlineui.bas` (screens), small changes to
  `menu.bas`, `screens.bi`, `beginnerchess.bas`, `settings.bas` (server address),
  build scripts; tests `tests/test_json.bas`, `tests/test_net.bas` (+ two-client
  test driver).
* Server: `server/` (package `beginnerchess_server/`, `tests/`, `migrations/`,
  `deployment/{systemd,nginx,scripts}/`, `README.md`, `config.example.toml`,
  `pyproject.toml`, `requirements.txt`).
* Docs: `docs/PROTOCOL.md`, `docs/ONLINE_GUIDE.md` (players),
  `server/README.md` + `docs/SERVER_DEPLOYMENT.md` (hosting), updates to
  README/ASSETS (third-party licences).

## 7. Third-party components and licences (2.0 additions)
| Component | Where | Licence |
|-----------|-------|---------|
| websockets | server | BSD-3-Clause |
| argon2-cffi (+ argon2-cffi-bindings, cffi, pycparser) | server | MIT / MIT / MIT-0 / BSD-3 |
| pytest (development only) | server tests | MIT |
| Python standard library (asyncio, sqlite3, ssl, tomllib) | server | PSF |
| libcurl | Linux client, loaded at run time, not shipped | curl licence (MIT/X style) |
| WinHTTP | Windows client, part of Windows | Windows component |
| Nginx (if installed on the VPS) | deployment | BSD-2-Clause |

No GPL component is used.

## 7a. VPS inspection

Before phase 9 the VPS was inspected read-only (operating system, Python,
listening ports, services, firewall). Nothing was installed or changed before
the owner approved the deployment plan. The details are kept privately; the
result was: Debian 13 with Python 3.13, no web server and no certificates yet,
a host firewall that only allowed SSH and existing services. Consequences for
phase 9: Nginx as TLS reverse proxy, certbot (Let's Encrypt, HTTP-01), a
`beginnerchess` system user and systemd service, and two **added** firewall
rules (80/tcp, 443/tcp); existing rules and services are never touched.

## 8. Needed from the owner (not blocking phases 2–8)
1. ~~VPS access~~ — provided by the owner (SSH key login; the sudo password is
   not stored anywhere).
2. **Approval** before anything is installed or changed on the VPS (Nginx,
   certificate, firewall, systemd service).
3. A Windows run of `build.bat test` at the end of phases 4, 5 and 10.
