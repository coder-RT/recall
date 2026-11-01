"""Request limits in front of the routers: how big a body may be (413), and how often the routes that call a model
or start the pipeline may be called per key (429, audited). In memory, per process: the API is one process on the
owner's Mac, so this stops a stuck loop or a leaked key from running up model calls, not a distributed attack."""

from __future__ import annotations

import hashlib
import re
import threading
import time
from dataclasses import dataclass, field

MB = 1024 * 1024

# (method, path pattern, largest body in bytes); the first match wins, the last line is everything else
BODY_LIMITS: list[tuple[str, re.Pattern[str], int]] = [
    ("PUT", re.compile(r"^/scans/[^/]+/parts/\d+$"), 64 * MB),  # a part (the spec's largest part_size)
    ("POST", re.compile(r"^/scans/[^/]+/results$"), 50 * MB),  # the pipeline's result
    ("POST", re.compile(r"^/guidance/sessions/[^/]+/verify$"), 25 * MB),  # one photo and its depth
    ("POST", re.compile(r"^/transcribe$"), 10 * MB),  # a spoken question
    ("*", re.compile(r".*"), 1 * MB),
]

# (method, path pattern, calls allowed per minute per key): the routes that reach a model or start the pipeline
RATE_LIMITS: list[tuple[str, re.Pattern[str], int]] = [
    ("POST", re.compile(r"^/ask$"), 30),
    ("POST", re.compile(r"^/transcribe$"), 30),
    ("POST", re.compile(r"^/guidance/sessions/[^/]+/verify$"), 20),
    ("POST", re.compile(r"^/scans/[^/]+/complete$"), 10),
]


def _match(table, method: str, path: str):
    return next((limit for m, pattern, limit in table if m in (method, "*") and pattern.match(path)), None)


def body_limit(method: str, path: str) -> int:
    return _match(BODY_LIMITS, method, path) or MB


@dataclass
class _Bucket:
    tokens: float
    at: float


@dataclass
class RateLimiter:
    """A token bucket per (key, route): `per_minute` calls, refilled evenly. Holds at most `max_buckets`; the oldest
    are dropped first, so a flood of new keys can't grow it without bound."""

    clock: callable = time.monotonic
    max_buckets: int = 2000
    _buckets: dict[tuple[str, str], _Bucket] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def allow(self, who: str, method: str, path: str) -> tuple[bool, int]:
        """(allowed, seconds to wait when not)."""
        per_minute = _match(RATE_LIMITS, method, path)
        if per_minute is None:
            return True, 0
        route = next(p.pattern for m, p, _ in RATE_LIMITS if m == method and p.match(path))
        now, rate = self.clock(), per_minute / 60.0
        with self._lock:
            b = self._buckets.pop((who, route), None) or _Bucket(float(per_minute), now)
            b.tokens = min(float(per_minute), b.tokens + (now - b.at) * rate)
            b.at = now
            ok = b.tokens >= 1.0
            if ok:
                b.tokens -= 1.0
            self._buckets[(who, route)] = b  # re-inserted: the dict's order is oldest use first
            while len(self._buckets) > self.max_buckets:
                self._buckets.pop(next(iter(self._buckets)))
        return ok, 0 if ok else max(1, int((1.0 - b.tokens) / rate) + 1)


def caller_id(authorization: str | None, client: str | None) -> str:
    """Who to count: a hash of the key they sent (never the key), else their address."""
    if authorization:
        return "k:" + hashlib.sha256(authorization.encode()).hexdigest()[:16]
    return "ip:" + (client or "unknown")
