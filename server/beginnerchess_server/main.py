"""Command-line entry point: ``python -m beginnerchess_server [--config FILE]``."""

from __future__ import annotations

import argparse
import asyncio
import logging
import signal
import ssl
import sys

from . import __version__
from .app import ChessServer, log_event
from .config import ConfigError, load_config


def setup_logging(level: str) -> None:
    # One line per event; journald adds the timestamp when run under systemd.
    logging.basicConfig(level=level.upper(), stream=sys.stderr,
                        format="%(asctime)s %(levelname)s %(name)s %(message)s")
    logging.getLogger().setLevel(level.upper())   # also if logging was configured before
    # The websockets library logs every failed handshake at INFO (scanners, bots), and at
    # DEBUG it logs message contents (which can contain passwords): never below WARNING.
    logging.getLogger("websockets").setLevel(logging.WARNING)


async def run(config_path: str | None) -> int:
    try:
        config = load_config(config_path)
    except (ConfigError, OSError, ValueError) as err:
        print(f"beginnerchess-server: configuration error: {err}", file=sys.stderr)
        return 2
    setup_logging(config.log_level)
    server = ChessServer(config)
    ssl_context = None
    if config.tls_cert_file:
        ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ssl_context.minimum_version = ssl.TLSVersion.TLSv1_2
        ssl_context.load_cert_chain(config.tls_cert_file, config.tls_key_file)
    await server.start(ssl_context)

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    await stop.wait()
    log_event("shutdown_requested")
    await server.stop()
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="beginnerchess-server",
                                     description="BeginnerChess multiplayer server")
    parser.add_argument("--config", help="TOML configuration file")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    args = parser.parse_args(argv)
    return asyncio.run(run(args.config))


if __name__ == "__main__":
    raise SystemExit(main())
