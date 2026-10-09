# BeginnerChess multiplayer server

The server behind **Play Online** in BeginnerChess 2.0: free, open source (MIT),
written in Python 3 (asyncio + `websockets`). It is the authority for every
online game.

> **Status:** feature-complete for protocol version 1 (phases 2–8 of the 2.0
> plan): transport and limits, chess rules, authoritative games and clocks,
> guests and accounts, lobby, quick match, challenges, Elo ratings,
> leaderboard, reconnection, restart recovery, administration, backups.
> Operations: `../docs/SERVER_OPERATIONS.md`; security: `../docs/SECURITY.md`.

## Run it locally

```sh
cd server
python3 -m venv .venv
.venv/bin/pip install -r requirements-test.txt
.venv/bin/python -m pytest              # run the tests
.venv/bin/python -m beginnerchess_server --config config.example.toml
```

With the example configuration it listens on `127.0.0.1:8765`
(`ws://127.0.0.1:8765/chess/ws`, health check `http://127.0.0.1:8765/chess/health`).
Stop it with Ctrl+C or `SIGTERM`: clients get a `server_shutdown` message and
the connections are closed cleanly.

## Configuration

See `config.example.toml`. Every setting can also be set with an environment
variable `BCS_<NAME>` (for example `BCS_LOG_LEVEL=DEBUG`). Unknown settings and
wrong values stop the server with a clear message. The configuration holds no
secrets.

## Layout

| path | content |
|------|---------|
| `beginnerchess_server/config.py` | settings, file + environment loading, validation |
| `beginnerchess_server/protocol.py` | message parsing/validation, error codes, close codes |
| `beginnerchess_server/connections.py` | per-connection state, rate limiting, connection limits |
| `beginnerchess_server/app.py` | WebSocket server, handshake, dispatch, health endpoint, shutdown |
| `beginnerchess_server/main.py` | command line, logging, signals |
| `beginnerchess_server/chess_rules.py` | chess rules (MIT, perft-verified), FEN, UCI, SAN |
| `beginnerchess_server/games.py` | authoritative games: moves, clocks, draws, results, PGN |
| `beginnerchess_server/players.py` | player identities and who is online where |
| `beginnerchess_server/lobby.py` | guest login, lobby list, quick match, challenges |
| `beginnerchess_server/accounts.py` | registration, login, sessions, profiles, history, leaderboard |
| `beginnerchess_server/ratings.py` | Elo ratings |
| `beginnerchess_server/persistence.py` | SQLite storage and migrations (`migrations/`) |
| `beginnerchess_server/limits.py` | sliding-window limits |
| `beginnerchess_server/administration.py`, `admin.py` | admin socket and command-line tool |
| `tools/loadtest.py` | load test |
| `tests/` | pytest suite (real WebSocket connections on a free local port) |
| `deployment/` | systemd, Nginx and install scripts (phase 9) |

The protocol is documented in `../docs/PROTOCOL.md`.

## Licences

The server code is MIT. Dependencies: `websockets` (BSD-3-Clause),
`argon2-cffi` and `argon2-cffi-bindings` (MIT), `cffi` (MIT-0), `pycparser`
(BSD-3-Clause); for the tests `pytest` (MIT) and `pytest-asyncio` (Apache-2.0).
No GPL code is used — the chess rules are BeginnerChess's own (see the plan,
§3.1).
