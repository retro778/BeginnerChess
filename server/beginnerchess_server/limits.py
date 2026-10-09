"""Sliding-window limits for expensive or abusable actions.

``SlidingWindow(count, seconds)`` allows at most ``count`` events per key in
any ``seconds`` long window. Keys are e.g. an IP address or a player id. Old
keys are forgotten automatically, so memory stays bounded.
"""

from __future__ import annotations

import time
from collections import deque


class SlidingWindow:
    def __init__(self, count: int, seconds: float, clock=time.monotonic, max_keys: int = 50_000):
        self.count, self.seconds, self.clock, self.max_keys = count, seconds, clock, max_keys
        self.events: dict[str, deque[float]] = {}

    def _prune(self, key: str, now: float) -> deque[float]:
        q = self.events.get(key)
        if q is None:
            return deque()
        while q and now - q[0] >= self.seconds:
            q.popleft()
        if not q:
            del self.events[key]
        return q

    def allow(self, key: str) -> bool:
        """Records an event for key if allowed; False if the limit is reached."""
        now = self.clock()
        q = self._prune(key, now)
        if len(q) >= self.count:
            return False
        if key not in self.events:
            if len(self.events) >= self.max_keys:          # bounded memory: drop the oldest key
                self.events.pop(next(iter(self.events)))
            self.events[key] = q
        q.append(now)
        return True

    def retry_after(self, key: str) -> float:
        q = self.events.get(key)
        if not q:
            return 0.0
        return max(0.0, self.seconds - (self.clock() - q[0]))
