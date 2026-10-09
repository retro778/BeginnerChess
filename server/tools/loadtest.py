"""Load test: many simulated players against a real server process.

    .venv/bin/python tools/loadtest.py --clients 200 --plies 40
    .venv/bin/python tools/loadtest.py --url wss://host/chess/ws --no-server ...   (an existing server)

Each simulated player connects, logs in as a guest, joins quick match and plays
random legal moves (thinking 0.1-0.5 s per move) until the game has the given
number of plies; then White resigns. Measured: connect+hello time, login time,
time until paired, move round trip (move sent -> move_accepted received),
errors; for a local server also its CPU time and memory (from /proc).
All simulated players come from one address, so the per-address limits are
raised for the test server only.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import random
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from websockets.asyncio.client import connect

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from beginnerchess_server.chess_rules import Board, Move  # noqa: E402


class Stats:
    def __init__(self):
        self.connect, self.login, self.paired, self.move_rtt = [], [], [], []
        self.errors: dict[str, int] = {}
        self.games_done = 0
        self.moves = 0

    def error(self, what: str) -> None:
        self.errors[what] = self.errors.get(what, 0) + 1


async def player(i: int, url: str, plies: int, stats: Stats, rng: random.Random) -> None:
    t0 = time.perf_counter()
    try:
        async with connect(url, compression=None, open_timeout=30, max_size=2**20) as ws:
            async def send(**m):
                await ws.send(json.dumps(m))

            async def wait(*types, timeout=60.0):
                while True:
                    msg = json.loads(await asyncio.wait_for(ws.recv(), timeout))
                    if msg["type"] in types:
                        return msg
                    if msg["type"] == "error":
                        stats.error(msg.get("code", "?"))

            await send(type="hello", protocol_version=1, client_name="LoadTest", client_version="1")
            await wait("welcome")
            stats.connect.append(time.perf_counter() - t0)
            t1 = time.perf_counter()
            await send(type="login_guest", nickname=f"L{i:05d}")
            await wait("logged_in")
            stats.login.append(time.perf_counter() - t1)
            t2 = time.perf_counter()
            await send(type="matchmaking_join", time_control={"initial_seconds": 600, "increment_seconds": 0})
            game = (await wait("game_started", timeout=120))["game"]
            stats.paired.append(time.perf_counter() - t2)
            gid, me = game["game_id"], game["your_color"]
            board = Board()
            while True:
                my_turn = board.turn == me
                if my_turn and len(board.move_stack) < plies and board.automatic_end() is None:
                    await asyncio.sleep(rng.uniform(0.1, 0.5))
                    m = rng.choice(board.legal_moves())
                    sent = time.perf_counter()
                    await send(type="move", game_id=gid, move=m.uci(), expected_ply=len(board.move_stack))
                    msg = await wait("move_accepted", "game_over")
                    if msg["type"] == "game_over":
                        break
                    stats.move_rtt.append(time.perf_counter() - sent)
                    stats.moves += 1
                    board.push(Move.from_uci(msg["move"]))
                    continue
                if my_turn and me == "w" and len(board.move_stack) >= plies:
                    await send(type="resign", game_id=gid)
                    await wait("game_over")
                    break
                msg = await wait("move_accepted", "game_over", timeout=120)
                if msg["type"] == "game_over":
                    break
                board.push(Move.from_uci(msg["move"]))
            stats.games_done += 1
    except Exception as err:
        stats.error(type(err).__name__)


def proc_sample(pid: int) -> tuple[float, int]:
    """(cpu seconds, rss kB) of a process."""
    with open(f"/proc/{pid}/stat") as f:
        parts = f.read().split(")")[1].split()
    ticks = os.sysconf("SC_CLK_TCK")
    cpu = (int(parts[11]) + int(parts[12])) / ticks
    rss = 0
    with open(f"/proc/{pid}/status") as f:
        for line in f:
            if line.startswith("VmRSS:"):
                rss = int(line.split()[1])
    return cpu, rss


def pct(values: list[float], p: float) -> float:
    if not values:
        return float("nan")
    values = sorted(values)
    return values[min(len(values) - 1, int(round(p / 100 * (len(values) - 1))))]


async def run(args) -> dict:
    server = None
    pid = None
    tmp = tempfile.mkdtemp(prefix="bc-load-")
    if not args.no_server:
        cfg = Path(tmp) / "load.toml"
        cfg.write_text(f'listen_port = {args.port}\ndatabase_path = "{tmp}/load.db"\nlog_level = "WARNING"\n'
                       f'max_connections = {args.clients + 100}\nmax_connections_per_ip = {args.clients + 100}\n'
                       f'new_connections_per_minute = {args.clients * 2}\n')
        server = subprocess.Popen([sys.executable, "-m", "beginnerchess_server", "--config", str(cfg)],
                                  cwd=Path(__file__).resolve().parents[1])
        pid = server.pid
        await asyncio.sleep(1.5)
    url = args.url or f"ws://127.0.0.1:{args.port}/chess/ws"
    stats = Stats()
    rng = random.Random(1)
    samples: list[tuple[float, float, int]] = []

    async def sampler():
        while True:
            if pid:
                cpu, rss = proc_sample(pid)
                samples.append((time.perf_counter(), cpu, rss))
            await asyncio.sleep(0.5)

    sampling = asyncio.create_task(sampler())
    started = time.perf_counter()
    tasks = []
    for i in range(args.clients):
        tasks.append(asyncio.create_task(player(i, url, args.plies, stats, random.Random(rng.random()))))
        if args.ramp > 0:
            await asyncio.sleep(args.ramp / args.clients)
    await asyncio.gather(*tasks)
    elapsed = time.perf_counter() - started
    sampling.cancel()
    if server is not None:
        server.terminate()
        server.wait(10)
    report = {
        "clients": args.clients, "plies_per_game": args.plies, "seconds": round(elapsed, 1),
        "games_completed": stats.games_done // 2, "moves": stats.moves,
        "moves_per_second": round(stats.moves / elapsed, 1),
        "errors": stats.errors,
        "connect_ms_p50_p95": [round(pct(stats.connect, 50) * 1000, 1), round(pct(stats.connect, 95) * 1000, 1)],
        "login_ms_p50_p95": [round(pct(stats.login, 50) * 1000, 1), round(pct(stats.login, 95) * 1000, 1)],
        "pairing_ms_p50_p95": [round(pct(stats.paired, 50) * 1000, 1), round(pct(stats.paired, 95) * 1000, 1)],
        "move_rtt_ms_p50_p95_p99_max": [round(pct(stats.move_rtt, q) * 1000, 2) for q in (50, 95, 99, 100)],
    }
    if len(samples) >= 2:
        (t_a, c_a, _), (t_b, c_b, _) = samples[0], samples[-1]
        report["server_cpu_percent_avg"] = round(100 * (c_b - c_a) / (t_b - t_a), 1)
        report["server_rss_mb_peak"] = round(max(s[2] for s in samples) / 1024, 1)
        peak = 0.0
        for (ta, ca, _), (tb, cb, _) in zip(samples, samples[1:]):
            if tb > ta:
                peak = max(peak, 100 * (cb - ca) / (tb - ta))
        report["server_cpu_percent_peak_0_5s"] = round(peak, 1)
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description="BeginnerChess load test")
    ap.add_argument("--clients", type=int, default=100, help="simulated players (even number)")
    ap.add_argument("--plies", type=int, default=40, help="moves per game before White resigns")
    ap.add_argument("--ramp", type=float, default=5.0, help="seconds to connect all players")
    ap.add_argument("--port", type=int, default=18799)
    ap.add_argument("--url", help="test an existing server instead of starting one")
    ap.add_argument("--no-server", action="store_true")
    args = ap.parse_args()
    report = asyncio.run(run(args))
    print(json.dumps(report, indent=2))
    return 0 if not report["errors"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
