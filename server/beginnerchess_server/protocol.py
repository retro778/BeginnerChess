"""Message format of the BeginnerChess protocol (see docs/PROTOCOL.md).

Every WebSocket text frame holds exactly one JSON object with a ``type``.
Requests from the client may carry a ``request_id``; the server copies it into
its answer so that the client can match answers to requests. Messages the
server sends on its own (events) carry no ``request_id``.
"""

from __future__ import annotations

import json
import re
from typing import Any

from . import PROTOCOL_VERSION

# ---------------------------------------------------------------------------
# Error codes (stable identifiers; the "message" text is for humans only)
# ---------------------------------------------------------------------------
BAD_JSON = "bad_json"                       # not valid UTF-8 JSON
BAD_MESSAGE = "bad_message"                 # not an object / missing or wrong fields
UNKNOWN_TYPE = "unknown_type"               # no such request type
HELLO_REQUIRED = "hello_required"           # first message must be "hello"
ALREADY_GREETED = "already_greeted"         # second "hello"
INCOMPATIBLE_VERSION = "incompatible_version"
RATE_LIMITED = "rate_limited"
NOT_AUTHENTICATED = "not_authenticated"     # the request needs a login (guest or account)
FORBIDDEN = "forbidden"                     # logged in, but not allowed
NOT_FOUND = "not_found"
CONFLICT = "conflict"                       # e.g. stale state, duplicate request
ILLEGAL_MOVE = "illegal_move"               # the move is not legal in the current position
NOT_YOUR_TURN = "not_your_turn"
GAME_OVER = "game_over"                     # the game has already ended
UNAVAILABLE = "unavailable"                 # feature switched off by the operator
INTERNAL_ERROR = "internal_error"

# WebSocket close codes in the private range 4000-4999.
CLOSE_INCOMPATIBLE = 4001
CLOSE_HELLO_TIMEOUT = 4002
CLOSE_TOO_MANY_VIOLATIONS = 4008
CLOSE_SESSION_REPLACED = 4009              # the same account logged in elsewhere
CLOSE_ADMIN = 4010                          # terminated by the operator
CLOSE_LOGIN_TIMEOUT = 4011                  # greeted, but no login in time

_TYPE_RE = re.compile(r"^[a-z][a-z0-9_]{0,31}$")
_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,64}$")
MAX_JSON_DEPTH = 8


class ProtocolError(Exception):
    """A request that must be answered with an ``error`` message."""

    def __init__(self, code: str, message: str, *, violation: bool = False, **extra: Any):
        super().__init__(message)
        self.code = code
        self.message = message
        #: True when the client clearly broke the protocol (counts towards closing).
        self.violation = violation
        #: Additional fields for the error message (e.g. the current ply).
        self.extra = extra


def _depth(value: Any, level: int = 0) -> int:
    if level > MAX_JSON_DEPTH:
        return level
    if isinstance(value, dict):
        return max([_depth(v, level + 1) for v in value.values()], default=level + 1)
    if isinstance(value, list):
        return max([_depth(v, level + 1) for v in value], default=level + 1)
    return level


def parse_message(text: str | bytes) -> dict[str, Any]:
    """Decodes one frame into a message dict, or raises ProtocolError."""
    if isinstance(text, bytes):
        raise ProtocolError(BAD_MESSAGE, "Binary frames are not used; send JSON text.", violation=True)
    try:
        msg = json.loads(text)
    except (json.JSONDecodeError, RecursionError):
        raise ProtocolError(BAD_JSON, "The message is not valid JSON.", violation=True) from None
    if not isinstance(msg, dict):
        raise ProtocolError(BAD_MESSAGE, "A message must be a JSON object.", violation=True)
    if _depth(msg) > MAX_JSON_DEPTH:
        raise ProtocolError(BAD_MESSAGE, "The message is nested too deeply.", violation=True)
    mtype = msg.get("type")
    if not isinstance(mtype, str) or not _TYPE_RE.match(mtype):
        raise ProtocolError(BAD_MESSAGE, "The message needs a valid 'type'.", violation=True)
    rid = msg.get("request_id")
    if rid is not None and (not isinstance(rid, str) or not _REQUEST_ID_RE.match(rid)):
        raise ProtocolError(BAD_MESSAGE, "Invalid 'request_id'.", violation=True)
    return msg


def encode(msg: dict[str, Any]) -> str:
    """Serializes a server message (compact, UTF-8 text, no NaN)."""
    return json.dumps(msg, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def error_message(code: str, message: str, request_id: str | None = None,
                  extra: dict[str, Any] | None = None) -> dict[str, Any]:
    msg: dict[str, Any] = {"type": "error", "code": code, "message": message, **(extra or {})}
    if request_id is not None:
        msg["request_id"] = request_id
    return msg


def reply(request: dict[str, Any], mtype: str, **fields: Any) -> dict[str, Any]:
    """An answer to ``request`` (copies its request_id)."""
    msg: dict[str, Any] = {"type": mtype, **fields}
    if request.get("request_id") is not None:
        msg["request_id"] = request["request_id"]
    return msg


# ---------------------------------------------------------------------------
# Field helpers: raise ProtocolError(BAD_MESSAGE) with a clear text.
# ---------------------------------------------------------------------------
def get_str(msg: dict[str, Any], name: str, *, max_len: int = 256, min_len: int = 0,
            pattern: re.Pattern[str] | None = None, optional: bool = False,
            default: str | None = None) -> str | None:
    value = msg.get(name)
    if value is None:
        if optional:
            return default
        raise ProtocolError(BAD_MESSAGE, f"'{name}' is missing.")
    if not isinstance(value, str) or not (min_len <= len(value) <= max_len):
        raise ProtocolError(BAD_MESSAGE, f"'{name}' must be text of {min_len}-{max_len} characters.")
    if pattern is not None and not pattern.match(value):
        raise ProtocolError(BAD_MESSAGE, f"'{name}' has an invalid format.")
    return value


def get_int(msg: dict[str, Any], name: str, *, lo: int, hi: int, optional: bool = False,
            default: int | None = None) -> int | None:
    value = msg.get(name)
    if value is None:
        if optional:
            return default
        raise ProtocolError(BAD_MESSAGE, f"'{name}' is missing.")
    if isinstance(value, bool) or not isinstance(value, int) or not (lo <= value <= hi):
        raise ProtocolError(BAD_MESSAGE, f"'{name}' must be a whole number from {lo} to {hi}.")
    return value


def get_bool(msg: dict[str, Any], name: str, *, optional: bool = False,
             default: bool | None = None) -> bool | None:
    value = msg.get(name)
    if value is None:
        if optional:
            return default
        raise ProtocolError(BAD_MESSAGE, f"'{name}' is missing.")
    if not isinstance(value, bool):
        raise ProtocolError(BAD_MESSAGE, f"'{name}' must be true or false.")
    return value


def get_obj(msg: dict[str, Any], name: str, *, optional: bool = False) -> dict[str, Any] | None:
    value = msg.get(name)
    if value is None:
        if optional:
            return None
        raise ProtocolError(BAD_MESSAGE, f"'{name}' is missing.")
    if not isinstance(value, dict):
        raise ProtocolError(BAD_MESSAGE, f"'{name}' must be an object.")
    return value


def check_hello(msg: dict[str, Any]) -> tuple[str, str]:
    """Validates a hello; returns (client_name, client_version)."""
    version = msg.get("protocol_version")
    if isinstance(version, bool) or not isinstance(version, int):
        raise ProtocolError(BAD_MESSAGE, "'protocol_version' must be a whole number.", violation=True)
    if version != PROTOCOL_VERSION:
        raise ProtocolError(
            INCOMPATIBLE_VERSION,
            "Your BeginnerChess version is incompatible with this multiplayer server. "
            "Please update BeginnerChess.")
    name = get_str(msg, "client_name", max_len=40, min_len=1)
    cversion = get_str(msg, "client_version", max_len=20, min_len=1)
    assert name is not None and cversion is not None
    return name, cversion
