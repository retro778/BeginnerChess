# Beginner Chess server — installation and self-hosting

How to run a Beginner Chess multiplayer server on a Debian or Ubuntu machine,
and the concrete plan for the official server at `freedomnet.tech`.
Daily operation (backups, administration, upgrades): `SERVER_OPERATIONS.md`.

## What you need

* Debian 12/13 or Ubuntu 22.04+ with Python 3.11 or newer, root access (sudo).
* A domain name pointing to the machine (A record; AAAA optional).
* TCP ports 80 and 443 reachable from the Internet (80 is needed for the free
  Let's Encrypt certificate and redirects; 443 carries the games).
* About 100 MB of disk and 100 MB of RAM (see the load test in
  `SERVER_OPERATIONS.md`).

## Layout after installation

```text
Internet ──wss://DOMAIN/chess/ws──▶ Nginx :443 (TLS, Let's Encrypt)
                                      │  /chess/ws, /chess/health
                                      ▼
                              127.0.0.1:8765  BeginnerChess server (Python, user "beginnerchess")
                                      │
                                      ▼
                    /var/lib/beginnerchess/beginnerchess.db (SQLite)
```

| path | content | owner / mode |
|------|---------|--------------|
| `/opt/beginnerchess/server` | program + virtual environment | root:beginnerchess, read-only for the service |
| `/etc/beginnerchess/server.toml` | configuration (no secrets) | root:beginnerchess 0640 |
| `/var/lib/beginnerchess` | database | beginnerchess 0750 |
| `/var/backups/beginnerchess` | daily backups (14 kept) | beginnerchess 0750 |
| `/run/beginnerchess/admin.sock` | administration socket | beginnerchess 0660 |
| `/etc/nginx/sites-available/beginnerchess` | Nginx site | root |

## Installation

```sh
# on your computer: copy the server folder (without its .venv)
rsync -a --exclude .venv --exclude __pycache__ server/ USER@HOST:beginnerchess-release/server/
# on the server
sudo DOMAIN=chess.example.org sh ~/beginnerchess-release/server/deployment/scripts/install.sh \
     ~/beginnerchess-release/server
```

The script (`deployment/scripts/install.sh`) is safe to run again. It installs
`nginx`, `certbot` and `python3-venv`; creates the system user `beginnerchess`;
copies the program; creates the virtual environment from `requirements.txt`;
installs the configuration (only if none exists); installs and starts the
hardened systemd service and the daily backup timer; configures Nginx (first
HTTP only, for the certificate); **adds** firewall rules for 80/tcp and 443/tcp
if ufw is used; gets a Let's Encrypt certificate (renewed automatically by
`certbot.timer`, Nginx reloaded by a deploy hook); switches Nginx to TLS; and
checks `https://DOMAIN/chess/health`. Set `CERT_EMAIL=you@example.org` to get
Let's Encrypt's expiry warnings (otherwise no e-mail address is registered).

**If the public check fails** although everything runs locally: a firewall
outside the machine (hosting provider's panel) may block ports 80/443.

### systemd

```sh
sudo systemctl status beginnerchess-server
sudo systemctl restart beginnerchess-server      # players are told, games are saved and continue
sudo systemctl stop beginnerchess-server
journalctl -u beginnerchess-server -f
systemctl list-timers beginnerchess-backup.timer certbot.timer
```

The service runs as `beginnerchess` without capabilities, with a read-only
system (`ProtectSystem=strict`), no access to home directories, private /tmp
and devices, a system-call filter, and limits (768 MB memory, 64 tasks, 4096
files). Source: `deployment/systemd/beginnerchess-server.service`.

### Removal

`sudo sh /opt/beginnerchess/server/deployment/scripts/uninstall.sh` removes the
service, the Nginx site, the program and the two firewall rules; add `--purge`
to delete the database and backups, `--remove-packages` to remove nginx and
certbot.

## Self-hosting notes

* Accounts, ratings and game histories belong to each server; players choose a
  server in *Play Online → Server address*. Ratings of different servers are
  never combined.
* The configuration keys are documented in `server/config.example.toml`.
* A server without a reverse proxy can also do TLS itself (`tls_cert_file`,
  `tls_key_file`), but then it must listen on a public address; the
  Nginx setup above is recommended.

---

## The official server: freedomnet.tech

**Deployed on 2026-10-09** with the owner's approval, using the steps above
(without a Let's Encrypt e-mail address). Results:

* `install.sh` finished without errors; its before/after check reported the
  existing services and firewall rules unchanged.
* Service `beginnerchess-server` active as user `beginnerchess` (hardening
  checked: `ProtectSystem=strict`, `NoNewPrivileges`, 768 MB memory limit);
  `admin status` works; the backup timer and `certbot.timer` are active.
* Certificate: Let's Encrypt for `freedomnet.tech`, valid until 2027-01-06,
  renewed automatically.
* Firewall: 80/tcp and 443/tcp added; nothing else changed.
* Checked from outside: `https://freedomnet.tech/chess/health` answers
  `{"status": "ok", ...}`; HTTP is redirected to HTTPS; `/`, `/admin`,
  `/.git/config` and path tricks answer 404; port 8765 is not reachable; SSH works.
* A complete game over `wss://freedomnet.tech/chess/ws` with the real
  certificate (no test CA): the BeginnerChess client test program (libcurl)
  against a Python test bot - 23 of 23 checks passed.
* Load test on the VPS: see `SERVER_OPERATIONS.md` (0 errors up to 1000
  simulated players).
* Update 2026-10-09: the phase-10 server fixes were installed as described in
  `SERVER_OPERATIONS.md` (*Upgrades*); migration 3 applied; other services and
  firewall unchanged.
* Windows clients (WinHTTP) played over this server on 2026-10-09.

### Protecting other things on the same machine

`install.sh` always compares the existing firewall rules before and after. If
the machine runs other services or sites, name them and the script also checks
that they are left exactly as they were (it never starts, stops or edits them):

```sh
sudo DOMAIN=chess.example.org PROTECT_SERVICES="postfix mysite" \
     PROTECT_PATHS="/var/www/mysite /etc/mysite" \
     sh ~/beginnerchess-release/server/deployment/scripts/install.sh ~/beginnerchess-release/server
```

### Undo

`sudo sh /opt/beginnerchess/server/deployment/scripts/uninstall.sh --purge --remove-packages`
removes what `install.sh` installed (including the two firewall rules); the
certificate files stay in `/etc/letsencrypt` unless removed with
`certbot delete --cert-name freedomnet.tech`.
