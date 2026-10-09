# Beginner Chess server — operations guide

For the person running a Beginner Chess multiplayer server (the official one at
`freedomnet.tech`, or your own). Installation is described in
`docs/SERVER_DEPLOYMENT.md`; this page covers daily operation.

Paths below are those of the standard installation:

| what | where |
|------|-------|
| program | `/opt/beginnerchess/server` (Python virtual environment in `.venv`) |
| configuration | `/etc/beginnerchess/server.toml` |
| database | `/var/lib/beginnerchess/beginnerchess.db` (SQLite, WAL mode) |
| admin socket | `/run/beginnerchess/admin.sock` (mode 0660, user/group `beginnerchess`) |
| backups | `/var/backups/beginnerchess/` |
| logs | journald: `journalctl -u beginnerchess-server` |

Shortcut used below:

```sh
admin() { sudo -u beginnerchess /opt/beginnerchess/server/.venv/bin/python \
          -m beginnerchess_server.admin --socket /run/beginnerchess/admin.sock "$@"; }
```

## Status and monitoring

```sh
admin status
```

prints version, uptime, connections, players online (guests/accounts), active
games, matchmaking queue, open challenges, database counts and schema version,
switched-on features, and the number and time of logged errors.

`https://freedomnet.tech/chess/health` answers `{"status": "ok", ...}` while the
server runs (for an external uptime monitor). It contains nothing private.

Logs: one line per event (`event=... key=value`), never passwords, session
tokens or message contents; IP addresses appear only in connection events and
warnings. `journalctl -u beginnerchess-server --since today`.

## Handling abuse

| command | effect |
|---------|--------|
| `admin kick NAME` | ends the player's connection and all their sessions (they can log in again) |
| `admin suspend NAME` | suspends the account (login refused), ends sessions and connection |
| `admin unsuspend NAME` | allows the account again |
| `admin set registration off` | no new accounts (until restart; change the config to keep it) |
| `admin set guests off` / `admin set rated_games off` | the same for guest play / rated games |

Built-in limits (configurable, see `config.example.toml`): message size 16 KiB;
20 messages at once then 5 per second per connection; 10 invalid requests close
the connection; 500 connections in total, 8 per address, 30 new connections per
address per minute; a connection must log in within 5 minutes; 5 registrations
per address per hour; 5 failed logins per name and 20 per address in 15 minutes;
10 challenges and 12 quick-match joins per player per minute; 10 remembered
logins per account. Running games are never interrupted by these limits.

## Backups

**Create** (safe while the server runs - SQLite's online backup API, then
`PRAGMA integrity_check` on the copy):

```sh
sudo -u beginnerchess /opt/beginnerchess/server/deployment/scripts/backup.sh
```

The `beginnerchess-backup.timer` runs this daily and keeps the newest 14
copies. Never copy the live `.db` file with `cp`: in WAL mode the newest data
may still be in the `-wal` file.

**Verify** a backup at any time:

```sh
admin --database /var/backups/beginnerchess/beginnerchess-20261009-030000.db integrity
```

**Restore**:

```sh
sudo systemctl stop beginnerchess-server
sudo -u beginnerchess cp /var/lib/beginnerchess/beginnerchess.db /var/lib/beginnerchess/before-restore.db
sudo -u beginnerchess cp BACKUP.db /var/lib/beginnerchess/beginnerchess.db
sudo rm -f /var/lib/beginnerchess/beginnerchess.db-wal /var/lib/beginnerchess/beginnerchess.db-shm
sudo systemctl start beginnerchess-server
admin status
```

(Games that were running at the time of the backup are restored too, with the
usual restart rules: account games continue, guest games end without result.)

## Upgrades and database migrations

1. Make a backup (above).
2. Copy the new `server/` files to `/opt/beginnerchess/server` (keep `.venv`),
   then `sudo -u beginnerchess .venv/bin/pip install -r requirements.txt`.
3. `sudo systemctl restart beginnerchess-server`. New database migrations
   (`server/migrations/NNNN_*.sql`) run automatically at start, each in one
   transaction; the applied versions are listed in the table `schema_migrations`
   (`admin status` shows the schema version).
4. Players are informed (`server_shutdown`), their games are saved and continue
   after the restart (account games).

**Rollback**: stop the server, restore the previous program files and the
backup made in step 1 (migrations are not reversible), start the server.

## Accounts and privacy requests

Players delete their own account in the game (*My profile → Delete my
account*). See `docs/PRIVACY.md` for what is stored. There is no password
recovery (no e-mail is stored); an operator cannot read passwords either.

## Load test

`server/tools/loadtest.py` starts a private server process and simulates
players (guest login, quick match, random legal moves with 0.1-0.5 s thinking
time, every move saved to the database). Measured on the development machine
(Intel i7-1165G7, 8 threads; the simulated players ran on the same machine),
2026-10-09:

| players at once | games | moves / s | errors | move round trip p50 / p95 / p99 | server CPU avg / peak (one core = 100 %) | server memory |
|---|---|---|---|---|---|---|
| 200 | 100 | 175 | 0 | 1.5 / 2.7 / 3.4 ms | 19 % / 34 % | 38 MB |
| 500 | 250 | 424 | 0 | 1.8 / 5.0 / 26 ms | 42 % / 80 % | 50 MB |
| 1000 | 500 | 783 | 0 | 21 / 116 / 136 ms | 75 % / 108 % | 67 MB |

The server uses one CPU core (one event loop); about 800 moves per second
saturate it on this machine.

**On the production VPS** (`freedomnet.tech`: 2 vCPUs AMD EPYC 9354P, 8 GB RAM,
Debian 13, Python 3.13), 2026-10-09: a private test server on `127.0.0.1:18799`
with its own temporary database, run as the `beginnerchess` user with the
installed program; the production service kept running. The simulated players
ran on the same two vCPUs, so they competed with the server for CPU time.

| players at once | games | moves / s | errors | move round trip p50 / p95 / p99 | server CPU avg / peak | server memory |
|---|---|---|---|---|---|---|
| 200 | 100 | 218 | 0 | 2.9 / 7.7 / 11.8 ms | 36 % / 54 % | 38 MB |
| 500 | 250 | 410 | 0 | 7.6 / 46 / 76 ms | 62 % / 97 % | 49 MB |
| 1000 | 500 | 656 | 0 | 138 / 309 / 389 ms | 87 % / 107 % | 68 MB |

At 1000 simulated players the server core is saturated (moves are still all
accepted, but slower). Real players think for seconds, not 0.1-0.5 s: 650 moves
per second would be several thousand people playing at the same time, far above
the configured limit of 500 connections (`max_connections`). These are
measurements of this test, not a promise of capacity.
