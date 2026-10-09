# Beginner Chess Online — security overview

What protects players and the server, and what cannot be guaranteed.

## Transport
* Only `wss://` (TLS) to anything other than `localhost`. Certificates are always
  verified: by libcurl with the system CA store on Linux, by Windows (WinHTTP)
  on Windows. There is no option to switch verification off. Tested: untrusted,
  expired, self-signed and wrong-host certificates are refused.
* The game server listens on `127.0.0.1` only; the public side is the TLS
  reverse proxy. `X-Forwarded-For` is believed only from the proxy.

## The server is the authority
* Every move is checked by the server's own chess rules (perft-verified, and
  cross-checked against the client's rules on 600 positions).
* Clocks, results, ratings and identities are decided by the server only. A
  client cannot send server messages (`game_over`, `rating_update` ... are
  unknown request types for clients); extra fields such as `rating` or clock
  values in requests are ignored (tested).
* Moves name the expected game state (`expected_ply`): stale, duplicated and
  out-of-order moves are rejected; a resent move is never played twice.
* Each game result and each rating change is recorded exactly once.

## Accounts
* Passwords: Argon2id (argon2-cffi), never stored or logged in plain text; at
  most two hashes are computed at a time (memory bound).
* Session tokens: 256 random bits; only their SHA-256 hash is stored; expire
  after 30 days without use; at most 10 per account; deleted at log-out,
  suspension and account deletion.
* Failed logins are throttled per name and per address; the error message is the
  same whether or not the name exists (and so is the time taken).
* "Remember me" on the client: DPAPI-encrypted on Windows, a 0600 file on Linux,
  never in the settings file.
* Guests cannot look like accounts ("Guest_" prefix, which account names may not
  use); names are unique among players online.

## Abuse and resource limits
Message size, message rate, invalid-request count, connections per address and
in total, new connections per minute, login time limit, registrations,
challenges and matchmaking per time, remembered logins per account, bounded
memory for every list kept by the server. Values: see
`docs/SERVER_OPERATIONS.md`. All SQL uses parameters.

## Operations
* Runs as an unprivileged system user (systemd hardening: see the deployment
  files). Administration only through a Unix socket with file permissions.
* Logs contain events, never passwords, tokens or message contents (tested; the
  WebSocket library's debug output, which would show message contents, is always
  kept off).
* Backups with SQLite's online backup API, verified with an integrity check.

## What cannot be guaranteed
* **Computer help ("engine cheating") cannot be detected or prevented.** The
  Beginner Chess client switches off its own hints, analysis and take-backs in
  online games, but nothing stops a player from using another chess program on
  the side. There is no automatic cheat detection. Rated games rely on fair play.
* Guest names are not protected after the guest leaves.
* There is no password recovery (no e-mail is stored).
* A modified client could show a player more than the official one; it can never
  make the server accept an illegal move, a different result or rating.
