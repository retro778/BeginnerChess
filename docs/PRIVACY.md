# Beginner Chess Online — privacy and stored data

Beginner Chess Online is free and needs no personal data. This page lists
everything the multiplayer server and the game store, for how long, and how
to delete it. (It describes the official server at `freedomnet.tech`; other
people's servers run the same software but are their own responsibility.)

## Never asked for

Real name, e-mail, address, phone number, payment details, age.

## On the server

| What | Why | How long |
|------|-----|----------|
| Guest nickname | shown to other players | while connected; stored only as the opponent's name in a game against an account (that player's match history) |
| Account: user name, creation date | your identity in games | until you delete the account |
| Account: password | logging in | **never stored** - only an Argon2id hash |
| Session tokens | "stay logged in" | only their SHA-256 hash; deleted at log-out, after 30 days without use, or with the account |
| Online rating, numbers of games/wins/draws/losses, rating history | profiles, leaderboard | until you delete the account |
| Finished games with at least one account (players' names, moves, result, time, PGN) | match history, replay | kept as public game records; see deletion below. **Games between two guests are not stored.** |
| Connection log (time, connection number, address, events such as "connected", "game over") | operating the server, stopping abuse | system log (journald), rotated by the system; never contains passwords, tokens or message contents |

Player profiles show only the user name, rating, statistics, month of
registration and recent games. Addresses, tokens and other private data are
never sent to other players.

## On your computer

* Settings file: server address, guest nickname, last user name (never the
  password).
* "Remember me" only: the session token, stored outside the settings file —
  on Windows encrypted with the Windows user's key (DPAPI) in
  `%APPDATA%\BeginnerChess\`; on Linux in `~/.beginnerchess/`, in a file only
  your user may read (permissions 0600; the content is not encrypted, so
  protect your user account). *Log out* deletes it.

## Deleting your account

*Play Online → My profile → Delete my account*, then type your password.
At once and permanently:

* the account, its password hash, sessions, rating and statistics are removed;
* the user name becomes free again;
* your finished games stay in your **opponents'** histories, but your name in
  them is replaced by "Deleted player" (games that then belong to nobody -
  against a guest or another deleted account - are deleted).

## No password recovery

There is no e-mail address, so a forgotten password cannot be reset. Write
your password down somewhere safe, or play as a guest.
