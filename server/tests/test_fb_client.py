"""End-to-end: the real BeginnerChess client network code (tests/test_online,
FreeBASIC) against this server over real TLS with certificate verification.

A throw-away test CA and a server certificate for "localhost" are created
with openssl; the client trusts the CA through BEGINNERCHESS_CAFILE (it adds a
trusted CA, it never switches verification off). A Python bot is the
opponent.
"""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import ssl
import subprocess
from pathlib import Path

import pytest
from websockets.asyncio.client import connect

from beginnerchess_server.app import ChessServer
from beginnerchess_server.config import Config

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "tests" / "test_online"

pytestmark = pytest.mark.skipif(not CLIENT.exists() or shutil.which("openssl") is None,
                                reason="client test program not built or openssl missing")


def make_certificates(folder: Path) -> tuple[Path, Path, Path]:
    def run(*args: str) -> None:
        subprocess.run(["openssl", *args], cwd=folder, check=True, capture_output=True)
    run("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "ca.key", "-out", "ca.pem",
        "-days", "2", "-subj", "/CN=BeginnerChess Test CA",
        "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign")
    run("req", "-newkey", "rsa:2048", "-nodes", "-keyout", "server.key", "-out", "server.csr",
        "-subj", "/CN=localhost")
    (folder / "ext.cnf").write_text("subjectAltName=DNS:localhost\nextendedKeyUsage=serverAuth\n")
    run("x509", "-req", "-in", "server.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial",
        "-out", "server.pem", "-days", "2", "-extfile", "ext.cnf")
    return folder / "ca.pem", folder / "server.pem", folder / "server.key"


@pytest.fixture
async def tls_server(tmp_path):
    ca, cert, key = make_certificates(tmp_path)
    ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ctx.load_cert_chain(cert, key)
    srv = ChessServer(Config(listen_host="127.0.0.1", listen_port=0, database_path=":memory:"))
    await srv.start(ctx)
    yield srv, ca
    await srv.stop()


async def run_client(*args: str, ca: Path | None) -> tuple[int, str]:
    env = dict(os.environ)
    env.pop("BEGINNERCHESS_CAFILE", None)
    if ca is not None:
        env["BEGINNERCHESS_CAFILE"] = str(ca)
    proc = await asyncio.create_subprocess_exec(str(CLIENT), *args, env=env,
                                                stdout=asyncio.subprocess.PIPE,
                                                stderr=asyncio.subprocess.STDOUT)
    out, _ = await asyncio.wait_for(proc.communicate(), 90)
    return proc.returncode, out.decode(errors="replace")


async def bot(url: str, ca: Path) -> None:
    """Joins quick match and plays its side of fool's mate."""
    ctx = ssl.create_default_context(cafile=str(ca))
    script = ["f2f3", "e7e5", "g2g4", "d8h4"]
    async with connect(url, ssl=ctx, compression=None) as ws:
        async def send(**msg):
            await ws.send(json.dumps(msg))
        await send(type="hello", protocol_version=1, client_name="TestBot", client_version="1")
        await send(type="login_guest", nickname="Bot")
        await send(type="matchmaking_join", time_control={"initial_seconds": 600, "increment_seconds": 0})
        colour, ply, game_id = None, 0, None
        async for raw in ws:
            msg = json.loads(raw)
            if msg["type"] == "game_started":
                colour, game_id, ply = msg["game"]["your_color"], msg["game"]["game_id"], 0
            elif msg["type"] == "move_accepted":
                ply = msg["ply"]
            elif msg["type"] == "game_over":
                return
            if colour and ply < 4 and (ply % 2 == 0) == (colour == "w"):
                await send(type="move", game_id=game_id, move=script[ply], expected_ply=ply)
                ply = -1        # wait for the confirmation


async def test_fb_client_plays_a_game_over_tls(tls_server):
    srv, ca = tls_server
    url = f"wss://localhost:{srv.port}/chess/ws"
    bot_task = asyncio.create_task(bot(url, ca))
    code, out = await run_client(url, ca=ca)
    print(out)
    await asyncio.wait_for(bot_task, 10)
    assert code == 0, out
    assert "Passed:" in out and "Failed: 0" in out


async def test_fb_client_refuses_an_untrusted_certificate(tls_server):
    srv, _ = tls_server
    code, out = await run_client("--expect-fail", f"wss://localhost:{srv.port}/chess/ws", ca=None)
    print(out)
    assert code == 0, out


async def test_fb_client_refuses_a_certificate_for_another_name(tls_server):
    srv, ca = tls_server
    # The certificate is for "localhost"; 127.0.0.1 reaches the same server under another name.
    code, out = await run_client("--expect-fail", f"wss://127.0.0.1:{srv.port}/chess/ws", ca=ca)
    print(out)
    assert code == 0, out


async def test_fb_client_cancel_while_connecting(tls_server):
    srv, ca = tls_server
    code, out = await run_client("--cancel-test", f"wss://localhost:{srv.port}/chess/ws", ca=ca)
    print(out)
    assert code == 0, out
