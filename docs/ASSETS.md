# Beginner Chess — Asset Licences

Every asset bundled with Beginner Chess must be legally redistributable.
Preferred licences: CC0 / public domain, or original work made for this
project (MIT, like the code).

| Asset | Files | Creator / source | Licence |
|-------|-------|------------------|---------|
| "Classic" and "Bold" chess piece sets | generated at run time by `modules/pieces.bas` (no image files) | original vector designs written for Beginner Chess | MIT (project licence) |
| Board themes (Classic, Wood, Marble, Simple, High Contrast) | generated at run time by `modules/board.bas` (procedural textures) | original | MIT (project licence) |
| User-interface font | generated at run time from the FreeBASIC runtime's built-in 8×16 bitmap font, smoothed by `modules/gfx.bas` | FreeBASIC runtime (gfxlib) | part of the FreeBASIC runtime library (LGPL with linking exception) |
| Opening book | `data/openings/book.txt` | written for Beginner Chess; opening moves and names are common chess knowledge | MIT (project licence) |
| Classic games | `data/games/classics.pgn` | game scores of Anderssen-Kieseritzky (1851), Anderssen-Dufresne (1852), Morphy-Duke Karl/Count Isouard (1858) - historical facts in the public domain; the short comments were written for Beginner Chess | public domain (moves) / MIT (comments) |
| Famous games | `data/games/famous.pgn` | historical game scores (1750-1997) are factual records in the public domain; introductions and comments were written for Beginner Chess | public domain (moves) / MIT (texts) |
| Lessons | `data/lessons/*.txt` | texts and exercises written for Beginner Chess; positions from historical games (e.g. the Immortal Game, 1851) are public-domain game records | MIT (project licence) |
| Puzzles | `data/puzzles/*.txt` | positions, hints and explanations composed for Beginner Chess (classic mating patterns are common chess knowledge) | MIT (project licence) |
| Screenshots in `docs/screenshots/` | `*.png` | produced by `beginnerchess --screenshots` | MIT (project licence) |
| Sound effects (move, capture, castle, promote, check, checkmate, illegal, click, victory, defeat, draw, solved, start) | generated at run time by `modules/audio.bas` (no audio files) | original synthesis code written for Beginner Chess | MIT (project licence) |
| Background music loop | generated at run time by `modules/audio.bas` | original composition/synthesis written for Beginner Chess | MIT (project licence) |

Third-party libraries (not assets, listed for completeness; both are
loaded at run time and optional):

| Library | Files | Licence |
|---------|-------|---------|
| BASS audio library (Un4seen Developments) | `bass.dll` (Windows), `libbass.so` (Linux) | BASS licence: free for non-commercial use |
| SQLite 3 | `sqlite3.dll` (Windows), system `libsqlite3` (Linux) | public domain |

No third-party sound or music files are bundled. Files a user puts into
`sound/effects/` or `sound/music/` are their own responsibility; anything
added to the distribution must be recorded here with filename, creator,
original source URL and licence.
