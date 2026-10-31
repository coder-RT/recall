"""The audit log: an append-only record of who did what to the home's memory and its sharing, and how it ended.

Kept on the Mac for the owner. Never a key, token or password; free text is trimmed. Robots and other agents appear
by role (their key says which), never by anything they claim about themselves.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum


class Actor(StrEnum):
    OWNER = "owner"  # the phone, with the device key
    ROBOT = "robot"  # a robot or other agent, with the robot key
    PIPELINE = "pipeline"  # the Mac's scan processing
    UNKNOWN = "unknown"  # no valid key


class Outcome(StrEnum):
    OK = "ok"
    REFUSED = "refused"  # by a switch, a key or the screen
    FAILED = "failed"


class Action(StrEnum):
    ROBOT_ACCESS_CHANGED = "robot_access.changed"
    ROBOT_EXPORT_READ = "robot_export.read"
    HOME_MEMORY_QUERY = "home_memory.query"
    AUTH_REFUSED = "auth.refused"
    OBJECT_CORRECTED = "object.corrected"
    OBJECT_FORGOTTEN = "object.forgotten"
    SCAN_INGESTED = "scan.ingested"
    SCAN_ERASED = "scan.erased"
    ARRIVAL_VERIFIED = "arrival.verified"


SECRET_WORDS = ("key", "token", "password", "secret", "authorization")
MAX_TEXT = 160


def clean(detail: dict) -> dict:
    """What may be kept: no field that names a secret, short strings, plain JSON values only."""
    out: dict = {}
    for k, v in detail.items():
        if any(w in k.lower() for w in SECRET_WORDS):
            continue
        if isinstance(v, str):
            out[k] = v if len(v) <= MAX_TEXT else v[: MAX_TEXT - 1] + "…"
        elif isinstance(v, (int, float, bool)) or v is None:
            out[k] = v
        elif isinstance(v, (list, tuple)):
            out[k] = [x for x in v if isinstance(x, (str, int, float, bool))][:20]
        elif isinstance(v, dict):
            out[k] = clean(v)
    return out


@dataclass(frozen=True)
class AuditEvent:
    id: str
    at: datetime
    actor: Actor
    action: Action
    outcome: Outcome
    target_type: str | None = None  # "object", "scan", "home", "session"
    target_id: str | None = None
    detail: dict = field(default_factory=dict)
    request_id: str | None = None
