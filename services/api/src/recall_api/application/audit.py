"""Records audit events for the use cases: the time from the clock, a new id, the request it happened in, and a
cleaned detail. Recording never breaks the action it records: a failure to write is logged and swallowed."""

from __future__ import annotations

import logging
from datetime import timedelta

from recall_api.application.ports import AuditLog, Clock
from recall_api.domain.audit import Action, Actor, AuditEvent, Outcome, clean
from recall_api.util.request_context import request_id

log = logging.getLogger("recall_api.audit")


class Auditor:
    def __init__(self, store: AuditLog, clock: Clock, new_id, retention_days: int = 90) -> None:
        self.store, self.clock, self.new_id, self.retention = store, clock, new_id, timedelta(days=retention_days)
        self._written = 0

    def __call__(
        self,
        action: Action,
        actor: Actor,
        outcome: Outcome = Outcome.OK,
        target_type: str | None = None,
        target_id: str | None = None,
        **detail,
    ) -> None:
        event = AuditEvent(
            self.new_id("ev"), self.clock.now(), actor, action, outcome, target_type, target_id, clean(detail),
            request_id.get(),
        )  # fmt: skip
        try:
            self.store.record(event)
            self._written += 1
            if self._written % 500 == 1:  # now and then, drop events past the retention period
                self.prune()
        except Exception:  # noqa: BLE001 - the audit must never break what it records
            log.exception("audit event not written: %s", action)

    def prune(self) -> int:
        """Drops events past the retention period, and records that it did: a gap in the log is always explained."""
        before = self.clock.now() - self.retention
        dropped = self.store.prune(before)
        if dropped:
            detail = clean({"dropped": dropped, "before": before.isoformat()})
            event = AuditEvent(self.new_id("ev"), self.clock.now(), Actor.SYSTEM, Action.AUDIT_PRUNED, Outcome.OK,
                               detail=detail)  # fmt: skip
            self.store.record(event)
        return dropped


class NoAudit:
    """For use cases built without an audit log (tests, scripts)."""

    def __call__(self, *a, **k) -> None:
        pass
