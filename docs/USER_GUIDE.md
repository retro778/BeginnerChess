# Beginner Chess — User Guide

For players, parents and teachers. Beginner Chess is a chess game and a
chess school in one program. You do not need to know chess to start.

## Starting

* **Linux:** run `./beginnerchess` in the Beginner Chess folder.
* **Windows:** double-click `beginnerchess.exe`.

The first time, Beginner Chess asks for your name (you can press *Skip*).
Everything is controlled with the mouse; hold the pointer over any button
for a moment to see a short explanation.

## Where should I begin?

| If you ... | Try |
|------------|-----|
| have never played chess | **Learn Chess → First steps**: the board, how every piece moves, check and checkmate |
| know the moves | **Chess Puzzles** (level 1) and **Practice** against the *Beginner* computer |
| win easily against Beginner | **Tournament → Career**: beat Alex, Maya, Leo ... one after another |
| want to understand your games | the **Review this game** button after a game |

## Main menu

* **Continue Game** — appears when a game was interrupted; brings you back
  to it.
* **Play Chess** — a game against the computer or against a friend at the
  same computer. Choose your colour, the difficulty (Beginner, Easy,
  Normal, Intermediate, Advanced) and the computer's style (Balanced,
  Defensive, Aggressive, Positional, Tactical, Material). You can also load
  a saved game, import a PGN file, or start from a position (FEN).
* **Play Online** — games against real people on the Internet, free, as a
  guest or with an account: quick match, challenges, online rating,
  leaderboard. Everything about it: [ONLINE_GUIDE.md](ONLINE_GUIDE.md).
* **Practice** — like Play Chess, but with help:
  * **Hint** shows the best move as an arrow and explains why it is good.
  * **Threats** colours your pieces in danger red and enemy pieces you
    could win green.
  * When you make a real mistake, the coach tells you what your opponent
    can now do, and the computer *waits*: press **Undo** to try again, or
    **Play on** to keep your move.
  * **Switch sides** lets you take over the other colour; **Analyze**
    opens the position in the analysis screen.
  * Practice games never change your rating.
* **Play Online** — real games against other people on the Internet, free.
  Beginner Chess connects to `freedomnet.tech` (a different server can be set
  with *Server address*). Choose a nickname and press *Play as guest*; pick the
  time (3, 5, 10, 15 or 30 minutes, with or without bonus seconds per move) and
  *Find an opponent*. The list on the right shows who is online. In the game:
  drag or click your pieces as usual; the clocks run on the server. *Offer draw*,
  *Resign*, *Claim draw* (three repetitions / 50 moves) and, before both sides
  have moved, *Cancel game*. Afterwards you can *Review* the game or *Save PGN*.
  Online games have no hints, no take-backs and no computer help. If the
  connection breaks, the game screen says so and *Back to lobby* takes you out.
  Nothing online is needed for the rest of Beginner Chess.
* **Tournament** — the *Career* ladder of seven computer opponents, and
  three round-robin tournaments. These games are rated: no take-backs.
  Every career and tournament game is kept in your own PGN file
  (`profiles/<you>/tournament_games.pgn`); *Import PGN → Replay* shows it
  move by move.
* **Learn Chess** — 68 lessons in six chapters: first steps, basic
  principles, tactics, strategy, endgames, and chess styles in history.
  Read each page, then solve the small tasks on the board. *Hint* helps
  if you are stuck.
* **Chess Puzzles** — find the best move: mates, winning material,
  forks, pins, defending, endgames and more. Difficulty is shown with
  stars; solved puzzles get a tick.
* **Famous Games** — replay great games from 1750 to today with
  explanations. *Play here* lets you continue a famous position yourself;
  *Review* lets Beginner Chess comment on every move. *Add PGN file* puts your
  own games in the library.
* **Analyze Position** — set up any position (*Set up position*, or *Enter
  FEN*) and the computer tells you who is better, the best move and why.
* **Player Profile** — your statistics, your player rating,
  achievements and recent games. Several players can share one computer:
  each has their own progress.
* **Options** — board colours, piece set, help dots, coordinates,
  animation speed, sound and music, window size, full screen,
  achievements on/off.

## Playing a game

* **Move:** click a piece, then the square to move to — or drag it.
  Dots show where the selected piece may go; rings show captures.
* If a move is not allowed, the coach box says why (for example "Your
  bishop is pinned").
* **Undo** takes back your last move (and the computer's answer).
* **Claim Draw** appears when the same position happened three times or
  50 moves passed without a capture or a pawn move (tournament rules).
  Five repetitions or 75 moves end the game automatically.
* **Offer Draw**, **Resign**, **Flip Board**, **Save / Share** (save slots,
  PGN export, copy the position as FEN).
* The game is saved automatically after every move.

Keyboard: `U` undo, `F` flip board, `Esc` back / main menu; in the game
viewer and review: arrow keys, `Home`, `End`, space (auto play).

## Your player rating

The rating starts at 400 and goes up when you win and down when you lose
against the computer (only games without take-backs count). It is an
estimate made by Beginner Chess, not an official FIDE rating.

## For teachers and parents

* Lessons and puzzles are plain text files in `data/lessons` and
  `data/puzzles`. You can change them or add your own; the file format is
  described at the top of `modules/lessons.bi` and `modules/puzzles.bi`.
  Run `tests/test_content` after editing: it checks every position and
  every solution.
* The opening book is `data/openings/book.txt`.
* Famous games come from `data/games/famous.pgn`.
* Your own sounds and music can go into `sound/effects` and `sound/music`
  (see the README files there).
* Beginner Chess works without internet and stores everything next to the
  program (or in `~/.beginnerchess` / `%APPDATA%\BeginnerChess` when that
  folder is read-only). Only **Play Online** connects to the Internet, and
  only when you press *Connect*; what the online server stores (a user name
  and your games - no e-mail, no real name) is explained in
  [PRIVACY.md](PRIVACY.md). Guests leave no account behind. There is no
  chat, so strangers cannot send children messages.

## If something does not work

* **Play Online cannot connect:** see *Connection troubleshooting* in
  [ONLINE_GUIDE.md](ONLINE_GUIDE.md).
* **No sound:** the BASS library is missing (`libbass.so` on Linux,
  `bass.dll` on Windows) or no sound card was found. The game works
  silently.
* **Famous Games says "The game database is not available":** SQLite
  was not found; the built-in games still work, but adding your own games
  is disabled.
* **A save file is "damaged":** it was edited or broken; Beginner Chess
  refuses it instead of loading a wrong position.
