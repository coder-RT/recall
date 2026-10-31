"""The audit log for the owner: mapping only. The device key only; robots never read it."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Query

from .deps import container, require_device_key
from .models import AuditEvent

router = APIRouter(tags=["audit"], dependencies=[Depends(require_device_key)])


@router.get("/audit", response_model=list[AuditEvent])
def list_audit_events(
    limit: int = Query(50, ge=1, le=500),
    action: str | None = None,
    actor: str | None = None,
    since: datetime | None = None,
    c=Depends(container),
) -> list[AuditEvent]:
    return [
        AuditEvent(id=e.id, at=e.at, actor=e.actor.value, action=e.action.value, outcome=e.outcome.value,
                   target_type=e.target_type, target_id=e.target_id, detail=e.detail, request_id=e.request_id)
        for e in c.audit_log.recent(limit, action, actor, since)
    ]  # fmt: skip
