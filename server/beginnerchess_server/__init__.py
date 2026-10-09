"""BeginnerChess multiplayer server.

Copyright (c) 2026 Ronen Blumberg. MIT License (see LICENSE.txt in the
project root).
"""

__version__ = "2.0.0"

#: Version of the client/server message protocol (independent of the
#: application version). Clients announce theirs in "hello".
PROTOCOL_VERSION = 1
