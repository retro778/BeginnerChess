# BeginnerChess - notes for Claude Code

FreeBASIC chess game + chess school for children/beginners. Full spec: `prompt.txt`.
Development is done in 10 phases; the status table is in `docs/ARCHITECTURE.md`
(all 10 phases done; version 1.0.0). **Version 2.0.0 = online multiplayer**, spec `prompt-version2.0.0.txt`,
plan and status in `docs/ONLINE_PLAN.md` (its own phases 1-10, all done), protocol in `docs/PROTOCOL.md`,
final report `docs/RELEASE_REPORT_2.0.0.md`, player guide `docs/ONLINE_GUIDE.md`.

## Build and test (Linux 64-bit, fbc 1.20 at ~/fbdev/bin/fbc)
- `./build.sh` builds `beginnerchess` and all test programs; `./build.sh test` also runs them.
- Must stay at **zero compiler warnings** (`-w all`). Flags: `-gen gcc -O 2 -mt`.
- Tests: `tests/test_core` (rules, perft), `test_engine`, `test_pgn`, `test_audio`, `test_content`
  (validates every lesson/puzzle with rules + engine), `test_famous` (+ `--nodb`), `test_profile`, `test_coach`.
- Visual check without a display: `./beginnerchess --screenshots DIR [WxH]` (BMP; convert with PIL to view).
  It uses DIR for saves/settings, never the real ones.
- Real-window tests: xdotool (`search --onlyvisible --name '^Beginner Chess$' | tail -1`, then
  `mousemove --window W x y` + plain `click 1`; absolute coordinates from getwindowgeometry are off).
  An autosave adds a "Continue Game" row to the main menu, shifting the buttons below it.
  Delete `beginnerchess.ini`, `profiles/`, `saves/*` afterwards.
- Crash hunting: build with `-exx -g` (runtime errors print file/line).
- Windows 32-bit build (`build.bat`) can only be compiled on Windows (no cross toolchain here); the user runs it
  on Windows. Tests must not use shell commands or /tmp: use tests/testutil.bi (Test_TempDir, Test_RemoveTree,
  Test_MakeDirs, Test_CopyFile). build.bat stops on the first failing test.
- Release: `./package.sh` (build + all tests + dist/*.tar.gz; `quick` skips tests); `package.bat` for Windows.
  Packages copy files explicitly (never `last-prompt.txt`, `fonts/hebega.cpi` - user files, unused).
- Public GitHub repo: https://github.com/retro778/BeginnerChess. `.gitignore` keeps out user files, builds, dist/,
  private/, CLAUDE.local.md, prompt*.txt. Before every commit: no secrets, no private VPS details (check with the grep in CLAUDE.local.md).
- test_content resets the engine (Engine_NewGame) before each puzzle, so results don't depend on order.

## Conventions / gotchas
- Module layering: rules -> notation -> game -> engine -> GUI. Only rules.bas decides legality.
- FreeBASIC is case-insensitive; avoid names that clash with keywords/builtins
  (seen: SQ/sq, cls, fb, base, out, append, frac, left, preset, name, open; a Const may not share a
  name with a function, e.g. ACH_COUNT vs Ach_Count). Var-len String arrays cannot have initializers.
- Mixing Boolean results with integer comparisons in AndAlso/OrElse gives warning 38: wrap with CBool().
- 32-bit Windows: Integer is 32-bit, and ULong values stay *unsigned* in expressions (on 64-bit they are promoted to
  signed Integer). Never subtract ULong-derived values without CInt (ARGB_* macros are CInt-wrapped for this; the
  missing cast once turned all gradients into stripes on Windows only). Check risky code by generating 32-bit C:
  `fbc -arch 386 -gen gcc -r file.bas` (linking 32-bit is impossible here). tests/test_gfx covers colour math.
- Fixed-size arrays cannot be ReDim'd: pass dynamic arrays to Text_Wrap etc.
- External libraries (BASS, SQLite) are loaded at run time with DyLibLoad; the game must keep
  working without them (BEGINNERCHESS_NOSOUND, BEGINNERCHESS_BASS, BEGINNERCHESS_SQLITE env vars for testing).
- Arrays passed to functions that ReDim Preserve them must be dynamic (Dim x() + ReDim).
- User decisions: MIT licence (Ronen Blumberg); FIDE claim rules (3-fold/50-move claimed,
  5-fold/75-move automatic); computer may resign only when it cannot win; opening book wanted.
- Phase 9: coach.bas/analysis.bas are GUI-free (tested by test_coach); review.bas, analyzeui.bas are screens.
  Practice judging lives in play.bas (CommitMove -> PracticeBeforeMove/PracticeAfterMove, practicePaused).
- Rebranded 2026-10-08 from ChessMaster to BeginnerChess (user-facing "Beginner Chess", title "BEGINNER CHESS",
  executables beginnerchess / beginnerchess.exe, main file beginnerchess.bas). The project folder is still
  named ChessMaster. Old names remain only for migration (settings.bas: chessmaster.ini, ~/.chessmaster,
  data/chessmaster.db) and their tests; internal `CM_VERSION` and the `CM...` save tags are kept on purpose
  (save compatibility). The computer opponent is called "Computer" in the UI.
- Server (2.0): `server/` Python package `beginnerchess_server`, venv `server/.venv` (not packaged), tests
  `cd server && .venv/bin/python -m pytest -q` (also run by `./build.sh test` when the venv exists).
  To stop a background server, save its PID at start (`... & echo $! > pidfile`); never `pkill -f`/`pgrep -f` with a
  pattern that appears in the current shell command - it kills the tool's own shell (happened twice).
- VPS / official server: private notes in CLAUDE.local.md and private/ (both git-ignored, never published).
- Client networking (2.0): modules/json.bas (strict parser, limits), net.bas (libcurl on Linux / WinHTTP on
  Windows, worker thread + mutex queues; NetConn per connection with a generation number: a connect that is
  cancelled is detached, never waited for; a worker frees its NetConn only when stale, else the main thread does),
  online.bas (protocol client, OnlineGame model, events). C `long` is 64-bit on Linux: pass LongInt to variadic
  curl_easy_setopt. Check Windows code: `fbc -target win32 -gen gcc -r -w all -mt modules/net.bas` then
  `gcc -m32 -malign-double -fsyntax-only -D'__stdcall=__attribute__((stdcall))' net.c`.
  E2E: server/tests/test_fb_client.py runs tests/test_online over TLS (test CA via BEGINNERCHESS_CAFILE).
  BEGINNERCHESS_CURL=<file> forces the libcurl file (a missing file simulates no libcurl).
- Server tests: read/write the live test database only via `server.db.query_one(...)` / `execute_now(...)`
  (they take the DB lock; raw `server.db.conn.execute` races with the worker thread -> flaky failures).
  Every test Config needs `database_path=":memory:"` (or tmp_path), else a stray server/beginnerchess.db appears.
  Only games with >= 1 account are stored (games between guests never).
- GUI tests with two windows: move them apart first (`xdotool windowmove W 0 0` / `1040 0`); overlapping windows
  swallow clicks. Pause ~0.5 s between mousemove and click; `windowactivate --sync` before typing.
