# Beginner Chess 2.0.0 — final development report

Date: 2026-10-09. Spec: `prompt-version2.0.0.txt`. Plan and phase history:
`docs/ONLINE_PLAN.md`.

The words used in this report mean:
* **implemented**: the code exists.
* **tested**: automated tests or a described manual test passed, on the stated
  platform.
* **deployed**: running on `freedomnet.tech`.
* **planned**: not done.

## 1. What was implemented

| feature | implemented | tested (Linux 64-bit) | deployed |
|---|---|---|---|
| Secure WebSocket client (TLS, certificate always verified): libcurl on Linux, WinHTTP on Windows | yes | yes (local TLS server, public server, bad-certificate sites) | – |
| Protocol client, online game model, automatic reconnection | yes | yes | – |
| Play Online screens: lobby, quick match, challenges, online game, profile, history with replay, leaderboard, account dialogs | yes | yes (two real windows; screenshots) | – |
| Guest play | yes | yes | yes |
| Accounts (register, log in, remember me, log out, delete) | yes | yes | yes |
| Server-authoritative games: rules, clocks, draws, resignation, cancel, timeout, abandonment | yes | yes | yes |
| Quick match (also rated, with a widening rating range), direct challenges | yes | yes | yes |
| Elo ratings, provisional period, leaderboard, match history | yes | yes | yes |
| Reconnection during a game; restart recovery of account games | yes | yes | yes |
| Limits and abuse protection, admin socket and CLI, backups | yes | yes | yes (daily backup timer) |
| VPS deployment: Nginx TLS proxy, Let's Encrypt, hardened systemd service, firewall | yes | yes (from outside) | yes |
| All offline features of 1.0 | unchanged | yes (all suites, screenshots of every screen, manual GUI test) | – |

## 2. What remains incomplete

* Nothing from the spec's deliverables. (The Windows 32-bit client, the last open
  point, was built, tested and packaged by the owner on Windows, and used for online
  play - see §12.)
* Not part of 2.0 (not required by the spec): chat, spectators, online
  tournaments, friends, puzzles online, password recovery, cheat detection,
  network-delay compensation on the clock.

## 3. Files created

Client:
* `modules/json.bi/.bas`
* `modules/net.bi/.bas`
* `modules/online.bi/.bas`
* `modules/onlineui.bas`
* `modules/tokenstore.bi/.bas`
* `tests/test_json.bas`
* `tests/test_tokenstore.bas`
* `tests/test_online.bas`
* `tests/online_check.bat`

Server (`server/`):
* `beginnerchess_server/`: `__init__`, `__main__`, `main`, `config`, `protocol`,
  `connections`, `app`, `chess_rules`, `games`, `players`, `lobby`, `accounts`,
  `ratings`, `persistence`, `limits`, `administration`, `admin`
* `migrations/0001`–`0003`
* `tests/`: 8 test modules + `conftest.py`
* `tools/loadtest.py`
* `deployment/`: `server.toml`, systemd service, backup service and timer,
  two Nginx configurations, `install.sh`, `uninstall.sh`, `backup.sh`
* `config.example.toml`, `requirements*.txt`, `pyproject.toml`, `README.md`

Documents:
* `docs/ONLINE_PLAN.md`
* `docs/PROTOCOL.md`
* `docs/PRIVACY.md`
* `docs/SECURITY.md`
* `docs/SERVER_DEPLOYMENT.md`
* `docs/SERVER_OPERATIONS.md`
* `docs/ONLINE_GUIDE.md`
* this report
* screenshots `online*.png`

## 4. Files modified

| file | change |
|---|---|
| `beginnerchess.bas` | dispatches the online screens, calls the online event pump every frame, shuts the network down at exit, adds online screenshots |
| `modules/gui.bi/.bas` | ordered key queue (no lost keys when typing fast), dialogs use up their Enter/Esc, masked password input, `UI_ClearToasts`, deeper idle frame pacing |
| `modules/menu.bas` | "Play Online" button, row height adapts to the number of buttons, About text |
| `modules/screens.bi` | new screen constants |
| `modules/settings.bi/.bas` | server address, nickname, user name, time control |
| `modules/chessdefs.bi` | `CM_VERSION` "2.0.0" |
| `build.sh`, `build.bat` | new modules and tests; `build.sh test` also runs the server tests |
| `package.sh`, `package.bat` | new documents and screenshots; `package.sh` also writes the server package |
| `README.md`, `docs/USER_GUIDE.md`, `CLAUDE.md` | 2.0 documentation |

## 5. Client networking design

* `net.bas` has one small interface: connect, state, send, receive, close.
  Each connection runs in a **worker thread**. The game loop never blocks on the
  network: it exchanges text messages with the worker through mutex-protected
  queues.
* **Linux:** libcurl ≥ 8.11, loaded at run time. It uses WebSocket
  `CONNECT_ONLY` mode (`curl_ws_send` / `curl_ws_recv` with `poll`) and the
  system CA store.
* **Windows:** WinHTTP, part of Windows 8 and newer. It uses the WebSocket
  upgrade and Windows' own certificate checks. A separate sender thread is
  needed, because WinHTTP's receive blocks.
* **Certificates are always verified.** There is no switch to turn this off.
  `ws://` is accepted only for `localhost`. `BEGINNERCHESS_CAFILE` can add a
  test CA, but never disables checking.
* **Cancelling a connection never waits:** a cancelled connection is detached
  and frees itself.
  * Every connection has a generation number, so messages from an old connection
    are ignored.
  * Ownership rule: the worker frees a connection only if it is stale; otherwise
    the main thread frees it.
* Without the library (no libcurl, or Windows 7) only Play Online shows a
  message. Everything else works (tested with `BEGINNERCHESS_CURL=/nonexistent`).
* `json.bas` is a strict parser with limits: depth 32, 50 000 nodes, 1 MiB.
  `online.bas` contains the protocol client, request ids, events, the
  `OnlineGame` model and reconnection: pauses of 1, 2, 4, 8 … seconds, for up to
  90 s, then the session is resumed.

## 6. Server architecture

* **Runtime:** Python 3.13, one asyncio event loop, `websockets`, and
  `argon2-cffi` for Argon2id in a pool of 2 workers.
* **Rules:** own MIT chess rules, perft-verified and cross-checked with the
  client's rules.
* **Modules:**
  * `app` (routing, limits, health endpoint, sweeper)
  * `connections` (clients, addresses, token buckets)
  * `lobby` (guests, lobby list, quick match, challenges)
  * `accounts`
  * `games` (authoritative game manager, clocks, timers, persistence, restore)
  * `ratings`
  * `persistence` (SQLite)
  * `administration` (Unix socket)
* **Deployment:** the server listens on `127.0.0.1:8765` only. Nginx terminates
  TLS for `wss://freedomnet.tech/chess/ws` and forwards it. The service runs
  under systemd as an unprivileged user with strict sandboxing.

## 7. Protocol design

`docs/PROTOCOL.md`. JSON text frames, `protocol_version` 1, `hello` first,
request ids, typed errors (`code`, message, extra fields such as
`retry_after`), close codes 4001–4011. Moves name the `expected_ply`, so
duplicate and out-of-date moves are harmless. Clients cannot send server
messages. The server sends snapshots after reconnecting.

## 8. Database design

SQLite in WAL mode. Numbered migrations run at start, each in one transaction.
Tables:
* `users`: name, Argon2id hash, rating, counts, status
* `sessions`: SHA-256 hash of the token, expiry
* `games`: active games after each move, finished games once
* `rating_history`
* `schema_migrations`

Only games with at least one account are stored (since migration 3). Online
backup API plus integrity check, daily, 14 copies kept.

## 9. Security implementation

`docs/SECURITY.md`. In short:
* TLS with verified certificates on every platform.
* The server is the only authority over moves, clocks, results and ratings.
* Argon2id passwords. Tokens stored only as hashes.
* Login throttling with the same answer whether a name exists or not.
* Limits on message size and rate, invalid requests, connections (total, per
  address, per minute), login time, registrations, challenges, matchmaking and
  sessions.
* All SQL uses parameters.
* Logs contain no secrets or message contents (tested).
* Unprivileged sandboxed service; admin access only through a Unix socket.
* Known: engine cheating cannot be prevented.

## 10. Test results (2026-10-09, Linux 64-bit)

* `./package.sh`: build with **0 warnings**, then all client test programs.

  | suite | checks | failures |
  |---|---|---|
  | core | 183 | 0 |
  | engine | 52 | 0 |
  | PGN | 53 | 0 |
  | audio | 45 | 0 |
  | content | 1402 | 0 |
  | famous | 70 | 0 |
  | famous without SQLite | 3 | 0 |
  | profile | 37 | 0 |
  | coach | 29 | 0 |
  | gfx | 13 | 0 |
  | JSON | 58 | 0 |
  | token store | 14 | 0 |
  | online client without libcurl | 1 | 0 |

* **Server: 184 pytest tests, 0 failures**. The full suite ran 12 times in a row
  without a failure after the fixes below. The tests cover:
  * the rules (perft);
  * transport and protocol;
  * games, lobby, accounts, challenges, ratings, reconnection and restart;
  * security and admin;
  * the FreeBASIC client over TLS, including certificate refusal and
    cancelling a connection.
* **Against the public server (real Let's Encrypt certificate):**
  * `tests/test_online` played a game against a test bot: 23/23 checks.
  * **Two real Beginner Chess windows** found each other in the lobby and played
    a game by mouse (1. f3 e5 2. g4 Qh4#). Both showed the same moves and the
    correct result.
* **Offline regression:** screenshots of all 44 screens. Without libcurl, the
  Play Online screen shows the "libcurl is not installed" message and the game
  goes on.
* **Load test on the VPS:** 200 / 500 / 1000 simulated players with 0 errors
  (details in `SERVER_OPERATIONS.md`).
* **Fixed in Phase 10:**
  * The server stored games between two guests, contrary to what players are
    told. Now they are not stored. Migration 3 removes old ones, and deleting an
    account removes games that then belong to nobody.
  * The history and game records included games still in progress. Now they
    don't.
  * A test wrote a stray `beginnerchess.db` into `server/`.
  * Tests read the shared database connection without its lock, which made them
    fail now and then. They now use `Database.query_one` / `execute_now`.
  * Client: the "(you)" label overlapped the next column for long names; the
    About page and the Play Online tooltip were updated.

## 11. Linux build results

FreeBASIC 1.20 (`-gen gcc -O 2 -mt -w all`): **0 warnings**.
`dist/BeginnerChess-2.0.0-linux-x86_64.tar.gz` and
`dist/BeginnerChess-Server-2.0.0.tar.gz` are written by `./package.sh`.

## 12. Windows build results

**Built, tested and packaged on Windows by the owner** (results below). Before
that, checked here (no Windows machine or 32-bit linker): `fbc -target win32 -gen gcc -r -w all -mt` on all 52 sources gave 0
warnings, and `gcc -m32 -fsyntax-only` on the generated C gave 0 errors. The
real test (`build.bat test`, `package.bat`, `tests\online_check.bat`, Play
Online) is done by the owner.

**Owner's first Windows run (2026-10-09):**
* `build.bat`: the program and all tests were built.
* `tests\online_check.bat` with WinHTTP:
  * TLS echo round trip: 4/4.
  * Self-signed and wrong-host certificates: refused, reason "certificate".
  * Cancelling a connection that hangs: 4/4.
  * The expired-certificate site was also refused, but with "did not answer in
    time".
* Investigation on Linux: badssl.com sometimes resets or drops connections
  before its certificate is seen (curl error 35, "Connection reset by peer"). The
  connection is refused in every case. The test now retries such network
  failures up to 3 times; a connection that actually opens still fails at once.

**Owner's second Windows run (2026-10-09):**
* `package.bat` ran `build.bat test`, which passed all suites. Token store:
  12/12 (the 2 Linux-only file-permission checks are not compiled on Windows).
* It wrote `dist\BeginnerChess-2.0.0-win32.zip`, checked here: a 32-bit PE
  program of the current code, with `bass.dll`, `sqlite3.dll`, documents and
  screenshots, and no user files.
* Server log: two Windows clients (BeginnerChess 2.0.0, WinHTTP) connected to
  `wss://freedomnet.tech/chess/ws` as guests and played a game that ended by
  resignation. As intended, it was not stored.
* The owner then confirmed the remaining checks: the updated
  `online_check.bat`, and online play including accounts. **Version 2.0.0 works
  on Linux 64-bit and Windows 32-bit.**

## 13. VPS deployment status

**Deployed 2026-10-09** on `freedomnet.tech` with the owner's approval. Details
and checks are in `SERVER_DEPLOYMENT.md`.
* Endpoint `wss://freedomnet.tech/chess/ws`; health page
  `https://freedomnet.tech/chess/health`.
* Let's Encrypt certificate, valid until 2027-01-06, renewed automatically.
* Firewall: only 80/tcp and 443/tcp were added.
* The other services on the VPS were verified unchanged.
* Phase 10 server fixes deployed the same day (approved): verified backup first,
  migration 3 ran (schema version 3, integrity ok), other services and the firewall
  compared before and after - unchanged; a public guest game afterwards was
  played (23/23) and, as intended, not stored.

## 14. Known limitations

* Engine cheating cannot be detected.
* No password recovery.
* Network delay is charged to the player's clock.
* Linux online play needs libcurl ≥ 8.11, which excludes Ubuntu 24.04's
  libcurl 8.5.
* The server is one process and one CPU core: about 650–800 moves per second.
  This is far above the configured limit of 500 connections.
* Guest names are not reserved after the guest leaves.

## 15. Recommended future improvements

1. Publish the release packages (Linux, Windows, server).
2. Add an external uptime monitor for `/chess/health`.
3. Clock latency compensation (a small lag allowance per move).
4. Optional e-mail for password recovery (needs a privacy decision).
5. Spectating games and an online puzzle of the day. Club/school servers with
   a shared invite code.
6. Fair-play tools: report button, admin game review, simple statistical
   checks.
7. Bundle a statically linked libcurl for older Linux distributions, or offer
   an AppImage.
