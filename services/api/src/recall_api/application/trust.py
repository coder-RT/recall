"""How sure Recall must be before it tells the user about a thing: the owner's level (Careful, Balanced, Everything),
kept on the Mac so the voice Guide, Find, room maps and robots all follow the same rule. Balanced by default."""

from __future__ import annotations

from recall_api.application.audit import NoAudit
from recall_api.application.ports import OwnerSettings
from recall_api.domain.audit import Action, Actor
from recall_api.domain.memory import Trust

KEY = "trust"


class TrustPolicy:
    def __init__(self, store: OwnerSettings | None = None, audit=None) -> None:
        self.store = store
        self.audit = audit or NoAudit()

    @property
    def level(self) -> Trust:
        value = self.store.get(KEY) if self.store else None
        try:
            return Trust(value) if value else Trust.BALANCED
        except ValueError:  # a value from a newer or older build: the default
            return Trust.BALANCED

    def set(self, level: Trust) -> Trust:
        was = self.level
        if self.store is None:
            raise RuntimeError("No settings store to keep the level in.")
        self.store.put(KEY, level.value)
        self.audit(Action.TRUST_CHANGED, Actor.OWNER, target_type="home", level=level.value, was=was.value)
        return self.level
