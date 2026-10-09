"""Server configuration: safe defaults, a TOML file, environment overrides.

Order of precedence (later wins):
1. the defaults below,
2. the TOML file (``--config`` or ``BEGINNERCHESS_CONFIG``),
3. environment variables ``BCS_<SETTING NAME IN CAPITALS>``.

The configuration never contains secrets: there are none to configure.
"""

from __future__ import annotations

import dataclasses
import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path


class ConfigError(ValueError):
    """Raised for unknown settings or values of the wrong type/range."""


@dataclass
class Config:
    # Network
    listen_host: str = "127.0.0.1"          # behind the reverse proxy: never public
    listen_port: int = 8765
    ws_path: str = "/chess/ws"
    health_path: str = "/chess/health"
    trusted_proxies: list[str] = field(default_factory=lambda: ["127.0.0.1", "::1"])
    # Optional direct TLS (normally the reverse proxy does TLS; leave empty then).
    tls_cert_file: str = ""
    tls_key_file: str = ""

    # Storage and logging
    database_path: str = "beginnerchess.db"
    admin_socket: str = ""                  # Unix socket for the admin CLI ("" = off)
    log_level: str = "INFO"

    # Limits
    max_connections: int = 500
    max_connections_per_ip: int = 8
    max_message_size: int = 16384           # bytes, client -> server
    hello_timeout: float = 10.0             # seconds to send "hello"
    heartbeat_interval: float = 20.0        # WebSocket ping every n seconds
    heartbeat_timeout: float = 20.0         # close if no pong within n seconds
    rate_limit_burst: int = 20              # messages that may arrive at once
    rate_limit_per_second: float = 5.0      # sustained messages per second
    max_violations: int = 10                # protocol/rate violations before closing
    new_connections_per_minute: int = 30    # per address (stops connection floods)
    login_timeout: float = 300.0            # greeted connections must log in within this time
    registrations_per_hour: int = 5         # per address
    challenges_per_minute: int = 10         # per player
    matchmaking_per_minute: int = 12        # joins per player
    sessions_per_user: int = 10             # remembered logins kept per account (oldest dropped)
    admin_socket_mode: str = "660"          # file permissions of the admin socket (octal)

    # Game policy
    reconnect_grace_seconds: int = 60
    session_days: int = 30                  # a login is remembered this long without use
    first_move_seconds: int = 30

    # Features
    registration_enabled: bool = True
    guest_access_enabled: bool = True
    rated_games_enabled: bool = True

    def validate(self) -> None:
        if not (0 <= self.listen_port <= 65535):
            raise ConfigError("listen_port must be 0..65535")
        if not self.ws_path.startswith("/") or not self.health_path.startswith("/"):
            raise ConfigError("ws_path and health_path must start with '/'")
        if self.ws_path == self.health_path:
            raise ConfigError("ws_path and health_path must differ")
        positive = ["max_connections", "max_connections_per_ip", "max_message_size",
                    "hello_timeout", "heartbeat_interval", "heartbeat_timeout",
                    "rate_limit_burst", "rate_limit_per_second", "max_violations",
                    "new_connections_per_minute", "login_timeout", "registrations_per_hour",
                    "challenges_per_minute", "matchmaking_per_minute", "sessions_per_user",
                    "reconnect_grace_seconds", "first_move_seconds", "session_days"]
        for name in positive:
            if getattr(self, name) <= 0:
                raise ConfigError(f"{name} must be positive")
        if self.max_message_size > 1_048_576:
            raise ConfigError("max_message_size is limited to 1 MiB")
        if bool(self.tls_cert_file) != bool(self.tls_key_file):
            raise ConfigError("tls_cert_file and tls_key_file must be set together")
        if self.log_level.upper() not in ("DEBUG", "INFO", "WARNING", "ERROR"):
            raise ConfigError("log_level must be DEBUG, INFO, WARNING or ERROR")


def _convert(name: str, raw: object, target: object) -> object:
    """Converts a TOML value or an environment string to the type of the default."""
    if isinstance(target, bool):
        if isinstance(raw, bool):
            return raw
        if isinstance(raw, str) and raw.lower() in ("1", "true", "yes", "on", "0", "false", "no", "off"):
            return raw.lower() in ("1", "true", "yes", "on")
        raise ConfigError(f"{name} must be true or false")
    if isinstance(target, int):
        if isinstance(raw, bool):
            raise ConfigError(f"{name} must be a whole number")
        try:
            return int(raw)  # type: ignore[arg-type]
        except (TypeError, ValueError):
            raise ConfigError(f"{name} must be a whole number") from None
    if isinstance(target, float):
        if isinstance(raw, bool):
            raise ConfigError(f"{name} must be a number")
        try:
            return float(raw)  # type: ignore[arg-type]
        except (TypeError, ValueError):
            raise ConfigError(f"{name} must be a number") from None
    if isinstance(target, list):
        if isinstance(raw, str):
            return [part.strip() for part in raw.split(",") if part.strip()]
        if isinstance(raw, list) and all(isinstance(x, str) for x in raw):
            return list(raw)
        raise ConfigError(f"{name} must be a list of strings")
    if not isinstance(raw, str):
        raise ConfigError(f"{name} must be text")
    return raw


def load_config(path: str | os.PathLike[str] | None = None,
                environ: dict[str, str] | None = None) -> Config:
    """Builds the configuration from defaults, an optional TOML file and the environment."""
    environ = dict(os.environ if environ is None else environ)
    cfg = Config()
    defaults = {f.name: getattr(cfg, f.name) for f in dataclasses.fields(Config)}

    path = path or environ.get("BEGINNERCHESS_CONFIG")
    if path:
        with Path(path).open("rb") as fh:
            data = tomllib.load(fh)
        # Settings may be at the top level or in a [server] table.
        if isinstance(data.get("server"), dict):
            data = {**{k: v for k, v in data.items() if k != "server"}, **data["server"]}
        for key, value in data.items():
            if key not in defaults:
                raise ConfigError(f"unknown setting '{key}' in {path}")
            setattr(cfg, key, _convert(key, value, defaults[key]))

    for key, default in defaults.items():
        env_name = "BCS_" + key.upper()
        if env_name in environ:
            setattr(cfg, key, _convert(env_name, environ[env_name], default))

    cfg.validate()
    return cfg
