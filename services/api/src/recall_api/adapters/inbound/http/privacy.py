"""Privacy facts for the phone's privacy note: mapping only, the facts come from application/describe_privacy.py."""

from __future__ import annotations

from fastapi import APIRouter, Depends

from recall_api.application.describe_privacy import describe_privacy

from .deps import container, require_device_key
from .models import Privacy

router = APIRouter(tags=["privacy"], dependencies=[Depends(require_device_key)])


@router.get("/privacy", response_model=Privacy)
def get_privacy(c=Depends(container)) -> Privacy:
    s = c.settings
    facts = describe_privacy(s.llm_provider, s.screen_provider, s.storage, c.robot_access.on, s.audit_retention_days)
    return Privacy.model_validate(
        {
            "stored_on": facts.stored_on,
            "sent": [vars(f) for f in facts.sent],
            "robot_access": facts.robot_access,
            "audit_days": facts.audit_days,
        }
    )
