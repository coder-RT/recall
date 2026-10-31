"""What another agent may send the Home Memory agent: one object name, nothing else (the schema in
resources/agents/find-object.input.schema.json, enforced here). Free text never reaches a model or a tool."""

from __future__ import annotations

import re

MAX_NAME = 40
_NAME = re.compile(r"^[A-Za-z0-9 -]+$")


class InvalidQuery(ValueError):
    """The input isn't a single valid object name; `reason` says what was wrong (for the log, not the caller)."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


def object_name(payload: object) -> str:
    """The object name from a structured query {"object": "<name>"}; InvalidQuery for anything else."""
    if not isinstance(payload, dict):
        raise InvalidQuery("not a data part")
    if set(payload) != {"object"}:
        raise InvalidQuery("only the field 'object' is accepted")
    name = payload["object"]
    if not isinstance(name, str) or not name.strip():
        raise InvalidQuery("object must be a non-empty string")
    if len(name) > MAX_NAME:
        raise InvalidQuery(f"object is longer than {MAX_NAME} characters")
    if not _NAME.match(name):
        raise InvalidQuery("object may contain only letters, digits, spaces and hyphens")
    return " ".join(name.split())
