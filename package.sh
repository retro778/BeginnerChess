#!/bin/sh
# BeginnerChess release package - Linux 64-bit
# Usage: ./package.sh        builds, tests and writes dist/BeginnerChess-<version>-linux-x86_64.tar.gz
#        ./package.sh quick  skips the (slow) content tests
set -e
cd "$(dirname "$0")"

VERSION=$(sed -n 's/^#define CM_VERSION "\(.*\)"/\1/p' modules/chessdefs.bi)
NAME="BeginnerChess-$VERSION-linux-x86_64"
OUT="dist/$NAME"

echo "== BeginnerChess $VERSION: build"
./build.sh
if [ "$1" != "quick" ]; then
    echo "== tests"
    ./tests/test_core
    ./tests/test_engine
    ./tests/test_pgn
    BEGINNERCHESS_NOSOUND=1 ./tests/test_audio
    ./tests/test_content
    ./tests/test_famous
    BEGINNERCHESS_SQLITE=/nonexistent ./tests/test_famous --nodb
    ./tests/test_profile
    ./tests/test_coach
    ./tests/test_gfx
    ./tests/test_json
    ./tests/test_tokenstore
    BEGINNERCHESS_CURL=/nonexistent ./tests/test_online --expect-fail wss://localhost/chess/ws
    if [ -x server/.venv/bin/python ]; then
        (cd server && .venv/bin/python -m pytest -q)
    else
        echo "NOTE: server tests skipped (no server/.venv - see server/README.md)"
    fi
fi

echo "== package $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/data" "$OUT/sound/effects" "$OUT/sound/music" "$OUT/saves" "$OUT/docs"
cp beginnerchess "$OUT/"
strip "$OUT/beginnerchess" 2>/dev/null || true
cp -r data/lessons data/puzzles data/openings data/games "$OUT/data/"
# data/beginnerchess.db is not shipped: BeginnerChess builds it from famous.pgn on first start.
cp sound/effects/README.txt "$OUT/sound/effects/"
cp sound/music/README.txt "$OUT/sound/music/"
cp README.md LICENSE.txt "$OUT/"
cp docs/ARCHITECTURE.md docs/ASSETS.md docs/USER_GUIDE.md docs/ONLINE_GUIDE.md docs/PRIVACY.md \
   docs/SECURITY.md "$OUT/docs/"
mkdir -p "$OUT/docs/screenshots"
# only the screenshots shown in the packaged documents
for f in $(cat README.md docs/USER_GUIDE.md docs/ONLINE_GUIDE.md | grep -o 'screenshots/[a-z_]*\.png' | sort -u); do
    cp "docs/$f" "$OUT/docs/$f"
done
# BASS is not part of the package (see README: put libbass.so next to the program for sound).
if [ -f libbass.so ]; then cp libbass.so "$OUT/"; fi

tar -C dist -czf "dist/$NAME.tar.gz" "$NAME"
echo "== done: dist/$NAME.tar.gz ($(du -h "dist/$NAME.tar.gz" | cut -f1))"

# Multiplayer server (platform independent Python; no virtual environment, caches or databases).
SNAME="BeginnerChess-Server-$VERSION"
SOUT="dist/$SNAME"
echo "== package $SOUT"
rm -rf "$SOUT"
mkdir -p "$SOUT/docs"
tar -C server --exclude=.venv --exclude=__pycache__ --exclude=.pytest_cache --exclude='*.db' \
    --exclude='*.db-wal' --exclude='*.db-shm' --exclude='*.egg-info' -cf - . | tar -C "$SOUT" -xf -
cp LICENSE.txt "$SOUT/"
cp docs/PROTOCOL.md docs/PRIVACY.md docs/SECURITY.md docs/SERVER_DEPLOYMENT.md docs/SERVER_OPERATIONS.md "$SOUT/docs/"
tar -C dist -czf "dist/$SNAME.tar.gz" "$SNAME"
echo "== done: dist/$SNAME.tar.gz ($(du -h "dist/$SNAME.tar.gz" | cut -f1))"
