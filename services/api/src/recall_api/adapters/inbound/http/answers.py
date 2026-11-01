"""Evidence for an answer, and the camera's view of a sighting: mapping only, the logic is in explain_answer.py."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response

from recall_api.application.explain_answer import EvidenceError

from .deps import container, require_device_key
from .models import Evidence

router = APIRouter(tags=["ask"], dependencies=[Depends(require_device_key)])


@router.get("/answers/{answer_id}/evidence", response_model=Evidence)
def get_evidence(answer_id: str, c=Depends(container)) -> Evidence:
    try:
        return Evidence.model_validate(c.explain_answer(answer_id))
    except EvidenceError as e:
        raise HTTPException(404, {"error": "not_found", "detail": e.message}) from e


@router.get("/observations/{observation_id}/crop", response_class=Response)
def get_crop(observation_id: str, c=Depends(container)) -> Response:
    try:
        jpeg = c.explain_answer.crop(observation_id)
    except EvidenceError as e:
        raise HTTPException(404, {"error": "not_found", "detail": e.message}) from e
    return Response(jpeg, media_type="image/jpeg")
