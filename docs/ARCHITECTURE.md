# Beginner Chess — Architecture and Development Notes

## Layering

```text
Chess Rules        modules/chessdefs.bi, modules/rules.bas      (board, moves, legality, draw rules)
      ↓
Notation           modules/notation.bas                         (SAN / coordinate moves)   [PGN later]
      ↓
Game Controller    modules/game.bas                             (move record, result, claims, undo)
      ↓
Explanations       modules/explain.bas                          (why a move is illegal; asks rules.bas)
      ↓
Chess Engine       modules/engine.bas                           (search + evaluation; uses rules only)
      ↓
User Interface     gfx.bas → pieces.bas → board.bas → gui.bas → menu.bas / play.bas
```

Rule: **only `rules.bas` decides what is legal.** The GUI, engine, lessons,
puzzles and PGN reader all call `Pos_GenerateLegal`, `Pos_FindLegalMove` or
`Game_PlayMove`.

## Board representation

* **0x88 mailbox**: `board(0 To 127)`, square = `rank * 16 + file`.
  `(sq And &h88) <> 0` means "off the board", so move generation needs no
  edge tables.
* Piece code = `colour * 8 + type` (`PC_WP = 1 ... PC_BK = 14`, `0` = empty).
* `Position` holds board, side to move, castling rights, en-passant square,
  half-move clock, full-move number, king squares, Zobrist hash and an
  **undo stack** (`MAX_HISTORY = 2048` plies). Make/unmake is used both for
  playing games and for engine search.
* Legal moves = pseudo-legal moves that do not leave the mover's king
  attacked (make → test → unmake). Simple and reliable; ~15–19 million
  perft nodes/s on the development machine, which is ample for an
  educational engine.

## Draw rules

* Threefold repetition: Zobrist hash comparison over the positions since
  the last capture/pawn move, same side to move. The en-passant square is
  hashed **only when a pawn can actually capture en passant**, so a
  harmless double pawn step does not make positions "different".
  (Limitation: an en-passant capture that is pseudo-legal but illegal
  because of a pin still counts as a difference. This is extremely rare.)
* Fifty-move rule: half-move clock ≥ 100.
* Insufficient material: K v K, K+minor v K, kings + bishops all on one
  square colour.
* **Policy (FIDE Laws of Chess)**: threefold repetition and the
  fifty-move rule must be *claimed* by the player to move — either for
  the current position or for the position their intended move creates
  (`Game_ClaimableDrawWithMove`; the GUI asks before playing such a
  move). Fivefold repetition and the 75-move rule end the game
  automatically. Checkmate always takes priority.

## User interface (Phase 2)

* **fbgfx**, 32-bit colour, double buffered (`ScreenSet 1, 0` +
  `ScreenCopy`). Alpha blending is done by `gfx.bas` itself because
  `GFX_ALPHA_PRIMITIVES` is not honoured by every gfxlib driver (e.g. the
  headless `GFX_NULL` driver used for screenshots).
* **Text**: FreeBASIC's built-in 8×16 font is captured once, enlarged
  4× with two EPX (scale2x) passes, then box-filtered to any size and
  turned into anti-aliased fbgfx custom fonts (cached per size/colour).
  No font files, no extra libraries.
* **Pieces**: a tiny shape language (polygons with quadratic curves,
  ellipses, rounded rectangles, detail lines) rasterised with 4×4
  super-sampling, outline and shading; built at any square size in ~30 ms.
* **Board themes**: procedural textures (value noise / turbulence) are
  rendered once into a board image per size and theme.
* **Immediate-mode GUI** (`gui.bas`): `If UI_Button(...) Then ...`.
  Mouse input uses the `ScreenEvent` queue so that very fast clicks
  (press and release within one frame) are never lost. Modal dialogs set
  `UI.blockInput` for everything underneath.
* **Screens** return the next screen id; the main loop in
  `beginnerchess.bas` switches between them.
* **Testing**: `beginnerchess --screenshots DIR` renders every screen
  headlessly with scripted states; the GUI was also exercised end-to-end
  with real X11 mouse/keyboard events (xdotool).

## Testing

`tests/test_core.bas`:

* Unit tests: FEN parsing/validation, hashing, castling (through/into/out
  of check, rights loss), en passant (including the pinned case),
  promotion and under-promotion, pins, double check, checkmate, stalemate,
  all draw rules, resignation/agreement, undo, SAN generation and parsing,
  move-list text.
* Perft against published reference counts (Chess Programming Wiki
  positions 1–6 plus a collection of special positions for illegal en
  passant, castling and promotion edge cases).
* `--full` runs deeper perft; `--perft` / `--divide` help with debugging.

## Engine (Phase 3)

* **Search**: negamax/alpha-beta with PVS at the root and inside, iterative
  deepening with a time limit (an iteration is not started after 40% of
  the budget), transposition table (1M × 16-byte entries, depth-preferred
  replacement, mate scores stored ply-independent), check extension,
  null-move pruning (R = 2, not in check/PV, needs non-pawn material),
  late-move reductions (1–2 plies for late quiet moves), mate-distance
  pruning, quiescence search (captures/promotions with delta pruning; all
  evasions when in check).
* **Draws inside the search**: a single repetition (within the game
  history plus search path) or the fifty-move limit counts as a draw;
  `contempt` from the style makes the engine avoid or welcome draws.
  Null moves (`Pos_MakeNullMove`) reset the half-move clock so that
  repetition checks never look across them.
* **Evaluation** (`ComputeTerms`): per-side middlegame/endgame values for
  13 terms, mixed by game phase (N/B = 1, R = 2, Q = 4, max 24). Attack
  maps are built once per evaluation and reused for mobility, king-zone
  pressure, space, centre control and hanging-piece threats. Material
  draw scaling (e.g. KR v KB, a lone minor piece). Verified by a mirror
  test: evaluation of a position equals that of its colour-flipped twin.
* **Styles**: two weight vectors per style — for the engine's own side
  and for the opponent's side — applied per term.
* **Levels**: depth, time, quiescence on/off, root noise, softmax
  temperature, candidate margin and an occasional "off moment"
  (`blunderChance`). Low levels compute an exact score for every root
  move and pick one with probability ∝ exp((score − best) / temperature),
  so weaker moves are chosen in proportion to how plausible they look.
  A found forced mate is never thrown away.
* **Threading**: `Engine_StartAsync` copies the position (with its game
  history) and runs the search in a FreeBASIC thread (8 MB stack);
  `Engine_PollAsync` collects the result; `Engine_StopAsync` signals a
  mutex-protected stop flag and joins the thread. The GUI never waits on
  the engine. Build with `-mt`.
* **Safety**: the chosen move is re-validated with `Pos_FindLegalMove`
  before it is returned.

## Opening book, resignation, files (Phase 4)

* **Opening book** (`openings.bas`): `ECO | name | SAN moves` lines are
  replayed from the start position; every (position hash, move) pair is
  stored with a weight = number of lines playing it. `Book_Probe` picks
  by weight. Names: the end position of a line carries its name; any
  position that only one named line passes through carries that name
  too, so variations are named as soon as they become distinct. The
  engine consults the book before searching, up to a level-dependent ply
  (Beginner 4 ... Advanced 24).
* **Resignation** (`Engine_ShouldResign`): forced mate against the
  engine, or score <= -900 for three consecutive engine moves; never if
  the opponent lacks mating material. Book moves never trigger it.
* **PGN** (`pgn.bas`): tag pairs with escapes, move numbers, SAN with
  annotation marks, `{}` and `;` comments (stored per ply in
  `ChessGame.comments`), nested variations and NAGs skipped, `%` escape
  lines, SetUp/FEN. Export writes the Seven Tag Roster, SetUp/FEN,
  PlyCount and comments, wrapped below 80 columns.
* **Save slots** (`savegame.bas`): PGN + `CM*` tags (opponent, level,
  style, human side, orientation, termination, saved-at, `CMFEN`).
  Loading replays the moves (restoring castling/en-passant rights, clocks
  and repetition history) and compares the result with `CMFEN` to detect
  damage. Writes go to a temporary file which then replaces the slot.
  Slot 0 is the autosave, written after every move and removed when the
  game ends.
* **Clipboard** (`clipboard.bas`): Win32 `OpenClipboard`/`CF_TEXT` under
  `#ifdef __FB_WIN32__` (declarations checked against the FreeBASIC
  winlibs headers); on Linux `xclip` / `xsel` / `wl-copy` through
  `Open Pipe`. `windows.bi` is included only in this module.

## Audio and settings (Phase 5)

* **BASS loaded at run time** (`DyLibLoad` + `DyLibSymbol`) through our
  own function-pointer types (`Stdcall` on Windows, `Cdecl` on Linux,
  matching bass.bi). No link dependency: a missing library, missing
  symbols or a failed `BASS_Init` only disables sound, with a reason in
  `Audio_StatusText`.
* **Synthesiser**: float buffers, additive tones (sine/triangle/soft
  square, glides, attack/exponential decay, click-free fades), bells
  with inharmonic partials, plucked strings, filtered-noise "wood knock";
  normalised and written as 16-bit PCM WAV in memory, loaded with
  `BASS_SampleLoad(mem)`. Music: 8 bars (C-Am-F-G twice) of pad, bass,
  arpeggios and a pentatonic melody rendered into a wrap-around buffer,
  so it loops without a seam; played as a looping memory stream. User
  files in `sound/effects` / `sound/music` take precedence.
* **Game sounds**: a move's sound is played when its animation lands;
  the end of a game (by any means) is detected once per frame and plays
  victory / defeat / draw / checkmate.
* **Settings**: `key=value` file with validation/clamping, written via a
  temporary file. Data folder: the program folder if writable, otherwise
  `~/.beginnerchess` or `%APPDATA%\BeginnerChess` (saves live there too).
  Window size/full-screen changes reopen the window between frames;
  offered sizes are limited by the desktop size measured before the first
  `ScreenRes`.

## Lessons and puzzles (Phase 6)

* **Content as data**: lessons and puzzles are keyword-per-line text
  files, loaded at start-up (`lessons.bas`, `puzzles.bas`). PAGE steps may
  use display-only positions (no kings needed); TASK steps must be legal.
  `PLAY` reaches a position by replaying SAN moves (used for real
  openings and famous games, so the positions are guaranteed to be
  correct).
* **Task goals** are checked by `Lesson_GoalMet`: exact moves, checkmate,
  check, capture, castling, promotion, any move by a given piece, "safe"
  (opponent has no mate in one afterwards), "best" (engine score within a
  margin of the engine's best move, depth 5 / 0.7 s), and play-out goals
  where the engine defends (async search) until mate/promotion within a
  move limit (stalemate, dead draw or move limit = try again).
* **Puzzles** accept the solution move, listed alternatives, or any
  mating move; opponent replies come from the solution line.
* **Validation**: `tests/test_content` replays every lesson goal/reply,
  checks squares in marks, and runs the engine (depth 8 / 2.5 s) on every
  puzzle move: the solution must be the engine's choice or score within
  0.4 pawns of it, and mate puzzles must end in mate. Several hand-made
  positions were corrected this way. `beginnerchess --screenshots` also
  renders every lesson step and puzzle once (run with an `-exx` build to
  catch runtime errors).
* **Board component** (`boardctl.bas`): selection, legal-move markers,
  click-click and drag, promotion chooser, animation with landing sound,
  explanations for illegal moves; used by lessons and puzzles.
* **Progress** (`progress.ini` in the data folder): completed lessons,
  solved puzzles, attempts; generic key/value store for Phase 8.
* **Frame rate**: 60 fps while there is input or animation, 20 fps when
  idle (about 10% CPU idle on the development machine).

## Famous games and SQLite (Phase 7)

* **db.bas** loads SQLite at run time (`libsqlite3.so.0` / `sqlite3.dll`,
  C calling convention on both platforms; checked against sqlite3.bi) and
  wraps open/exec/prepare/bind/step/column/finalize. Text is bound with
  `SQLITE_TRANSIENT`; errors come from `sqlite3_errmsg`.
* **Schema** (`famous.bas`): `meta`, `famous_games`, `game_moves`
  (one row per ply with SAN and comment), `openings` (copy of the opening
  book). Lessons and puzzles stay in text files - SQLite is used where it
  helps: a growing, searchable game library that also keeps the
  player's own games.
* **Built-in content** lives in `data/games/famous.pgn`; a size+FNV
  signature in `meta` triggers an automatic rebuild of the built-in rows
  when the file changes (user rows are kept). Imports skip duplicates
  (same players, date and length) and report unreadable games.
* **Fallback**: without SQLite (or if the database cannot be opened) the
  library is read straight from the PGN file and the "Add PGN file"
  button is disabled with an explanation.
* **Viewer**: positions are rebuilt from the parsed game's move list
  (`g.pos.undoStack`), single steps forward are animated with sound;
  "Play from here" undoes the recorded game to the chosen ply and hands it
  to the game screen (history kept, so repetition rules still work).
* Lesson about robustness: every helper that grows an array with
  `ReDim Preserve` (Text_Wrap, Pgn_SplitGames) must receive a dynamic
  array; fixed arrays caused a crash and a heap error during testing.

## Profiles, career and tournaments (Phase 8)

* **Profiles** (`profile.bas`): one folder per player with `profile.ini`
  (key=value statistics, achievements `ach.<id>=date`, tournament state
  `tour.*`, unknown keys preserved), `progress.ini` (lessons/puzzles;
  `Profile_Select` points the progress module at it) and `history.txt`.
  Plain files - no SQLite needed, robust to damage.
* **Rating**: Elo, expected = 1/(1+10^((Ropp-R)/400)), K = 40 for the
  first 20 rated games then 24, floor 100, start 400. Rated = against the
  computer, no take-backs, started from the normal position, at least two
  plies. Computer levels count as 500/800/1100/1400/1700; career and
  tournament opponents have their own ratings.
* **Career** (`career.bas`): 7 opponents (level + style + bio); winning
  against the current one advances `careerStage`. Rematches are allowed.
* **Tournaments**: 4 opponents + player, single round robin. The player
  meets opponent i in round i+1 (colours alternate); the six games among
  the opponents are scheduled over the four rounds and simulated from
  the Elo expectation with a 25% draw band. Results are stored as a 5x5
  matrix string; ties for first count in the player's favour. Tiers
  unlock by rating (700 / 1100) or by winning the tier below.
* **Recording**: the game screen records each finished game once
  (`RecordFinishedGame`), then career/tournament updates and
  `App_CheckAchievements`, which also runs after lessons, puzzles and
  famous games. New achievements appear as toasts (`UI_ShowToast`).

## Coach, analysis, practice (Phase 9)

* **Coach** (`coach.bas`, no GUI): static exchange evaluation (swap list
  with x-ray attackers), `Coach_ThreatOn` (best SEE of any capture on a
  square, also "attacked by a cheaper piece"), and `Coach_ExplainMove`,
  a priority list of heuristics: mate, check+fork, captures (unprotected
  / worth more / wins material / trade), promotion, stops a mate threat,
  saves an attacked piece, fork, protects a piece, castling, check,
  passed pawn, development and centre pawns (opening only), rook on an
  open file, king activity (endgame), and a generic fallback.
  `Coach_ExplainThreat` describes the opponent's best reply after a
  mistake. Explanations are teaching aids, not proofs.
* **Analysis** (`analysis.bas`): one synchronous engine search (250 ms,
  level Advanced, no book/contempt/noise) per position, one step per
  frame so the GUI stays responsive. A move's loss is measured in win
  chance, 100/(1+10^(-cp/400)): Best <= 2, Good <= 6, Inaccuracy <= 12,
  Mistake <= 22, else Blunder (percentage points). Moves still in the
  opening book are "Book" and never judged.
* **Review** (`review.bas`): progress overlay, per-side counts, advantage
  graph (clickable), board arrows (played move blue / red for mistakes,
  better move green), details cached per ply, Next mistake (wraps).
* **Analyze** (`analyzeui.bas`): asynchronous engine (3 s) restarted when
  the position changes; editor validates the position with
  `Pos_LoadFEN` (castling rights inferred from the king/rook squares).
* **Practice** (`play.bas`): before each human move a 250 ms search gives
  the best move and score; after the move a second search gives the new
  score. A win-chance drop of at least 15 points pauses the computer
  (`practicePaused`) and shows the warning until Undo or Play on. The
  practice flag is stored in saves (`CMPractice` tag).

## Development environment (as found at the start of the project)

| Item | Linux 64-bit (dev machine) | Windows 32-bit |
|------|----------------------------|----------------|
| Compiler | FreeBASIC 1.20.0 linux-x86_64 (`~/fbdev/bin/fbc`) | FreeBASIC 1.10.1 winlibs, `fbc32.exe` |
| BASS | `/usr/local/lib/libbass.so` (x86_64), header `bass.bi` (`#inclib "bass"`) | `bass.dll` (PE32 i386) in project root; `lib/win32/libbass.dll.a` ships with FreeBASIC |
| SQLite 3 | system `libsqlite3.so`, header `sqlite3.bi` (`#inclib "sqlite3"`) | `sqlite3.dll` (PE32 i386) in project root; **no** import library ships with FreeBASIC — link directly against the DLL (`-p <dir with sqlite3.dll>`) or build `libsqlite3.dll.a` from `sqlite3.def` with `dlltool` |

The Linux FreeBASIC installation has no win32 target libraries and wine is
not installed, so the Windows build must be produced on Windows (or a
machine with the win32 FreeBASIC package). Code is kept portable: no
OS-specific APIs in the chess core; future OS-specific code will be
guarded with `#ifdef __FB_WIN32__` / `#ifdef __FB_LINUX__`.

## Phase plan

| Phase | Content | Status |
|-------|---------|--------|
| 1 | Chess core, rules, FEN, SAN, game controller, tests/perft | **done** |
| 2 | Graphical board (fbgfx), mouse, highlights, move list, new game | **done** |
| 3 | Engine: evaluation, negamax + alpha-beta, iterative deepening, quiescence, TT, levels, styles | **done** |
| 4 | Save/load, PGN import/export, FEN copy (+ opening book, resignation) | **done** |
| 5 | Audio (BASS, optional) and settings file | **done** |
| 6 | Lessons and puzzles | **done** |
| 7 | SQLite famous-games database + game viewer | **done** |
| 8 | Tournament/career mode, profiles, statistics, achievements | **done** |
| 9 | Game analysis and educational explanations, hints (+ Practice mode, Analyze Position) | **done** |
| 10 | Testing, optimisation, documentation, packaging | **done** |
