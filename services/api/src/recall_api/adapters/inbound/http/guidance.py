"""Guidance routes: mapping only."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from recall_api.application.plan_guidance import GuidanceError

from .deps import container, not_implemented, require_device_key
from .models import GuidanceRequest, GuidanceSession

router = APIRouter(tags=["guidance"], dependencies=[Depends(require_device_key)])


@router.post("/guidance/sessions", response_model=GuidanceSession)
def start_guidance(body: GuidanceRequest, c=Depends(container)) -> GuidanceSession:
    try:
        g = c.guidance.start(body.home_id, body.object_id, list(body.pose.matrix), body.tracking.value)
    except GuidanceError as e:
        raise HTTPException(e.status, {"error": e.code, "detail": str(e)}) from e
    return GuidanceSession.model_validate(g)


@router.post("/guidance/sessions/{session_id}/verify")
def verify(session_id: str):
    raise not_implemented("The arrival check")
