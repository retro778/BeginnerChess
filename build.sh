#!/bin/sh
# BeginnerChess build script - Linux 64-bit
# Usage: ./build.sh          build the program and the tests
#        ./build.sh test     build, then run the core tests
set -e
cd "$(dirname "$0")"

FBC="${FBC:-fbc}"
FLAGS="-w all -gen gcc -O 2 -mt"
CORE="modules/rules.bas modules/notation.bas modules/game.bas modules/engine.bas modules/openings.bas modules/pgn.bas modules/savegame.bas modules/progress.bas modules/lessons.bas modules/puzzles.bas modules/db.bas modules/famous.bas modules/profile.bas modules/career.bas modules/coach.bas modules/analysis.bas"
GUI="modules/audio.bas modules/clipboard.bas modules/files.bas modules/gfx.bas modules/pieces.bas modules/board.bas modules/gui.bas modules/explain.bas modules/settings.bas modules/menu.bas modules/play.bas modules/boardctl.bas modules/learn.bas modules/famousui.bas modules/profileui.bas modules/tournamentui.bas modules/review.bas modules/analyzeui.bas modules/json.bas modules/net.bas modules/online.bas modules/onlineui.bas modules/tokenstore.bas"

echo "Building beginnerchess..."
$FBC $FLAGS -s gui beginnerchess.bas $CORE $GUI -x beginnerchess

echo "Building tests..."
$FBC $FLAGS tests/test_core.bas $CORE -x tests/test_core
$FBC $FLAGS tests/test_engine.bas $CORE -x tests/test_engine
$FBC $FLAGS tests/test_pgn.bas $CORE -x tests/test_pgn
$FBC $FLAGS tests/test_audio.bas modules/audio.bas modules/settings.bas -x tests/test_audio
$FBC $FLAGS tests/test_content.bas $CORE -x tests/test_content
$FBC $FLAGS tests/test_famous.bas $CORE -x tests/test_famous
$FBC $FLAGS tests/test_profile.bas $CORE -x tests/test_profile
$FBC $FLAGS tests/test_coach.bas $CORE -x tests/test_coach
$FBC $FLAGS tests/test_gfx.bas modules/gfx.bas -x tests/test_gfx
$FBC $FLAGS tests/test_json.bas modules/json.bas -x tests/test_json
$FBC $FLAGS tests/test_tokenstore.bas modules/tokenstore.bas -x tests/test_tokenstore
$FBC $FLAGS tests/test_online.bas modules/online.bas modules/net.bas modules/json.bas -x tests/test_online

if [ "$1" = "test" ]; then
    ./tests/test_core
    ./tests/test_engine
    ./tests/test_pgn
    ./tests/test_audio
    ./tests/test_content
    ./tests/test_famous
    BEGINNERCHESS_SQLITE=/nonexistent ./tests/test_famous --nodb
    ./tests/test_profile
    ./tests/test_coach
    ./tests/test_gfx
    ./tests/test_json
    ./tests/test_tokenstore
    # Without libcurl, online play must fail with a message (no crash, no network use).
    BEGINNERCHESS_CURL=/nonexistent ./tests/test_online --expect-fail wss://localhost/chess/ws
    # Multiplayer server (only if its Python environment exists: see server/README.md);
    # this also runs tests/test_online against a local TLS server.
    if [ -x server/.venv/bin/python ]; then
        (cd server && .venv/bin/python -m pytest -q)
    fi
fi
echo "Done."
