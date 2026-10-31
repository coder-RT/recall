"""Evidence for an answer, and the camera's view of a sighting: mapping only, the logic is in explain_answer.py."""

from __future__ import annotations

import io

from fastapi import APIRouter, Depends, HTTPException, Response
from PIL import Image

from recall_api.application.explain_answer import EvidenceError

from .deps import container, require_device_key
from .models import Evidence

router = APIRouter(tags=["ask"], dependencies=[Depends(require_device_key)])
MARGIN = 0.25  # around the box, so the thing is seen in its place


@router.get("/answers/{answer_id}/evidence", response_model=Evidence)
def get_evidence(answer_id: str, c=Depends(container)) -> Evidence:
    try:
        return Evidence.model_validate(c.explain_answer(answer_id))
    except EvidenceError as e:
        raise HTTPException(404, {"error": "not_found", "detail": e.message}) from e


@router.get("/observations/{observation_id}/crop", response_class=Response)
def get_crop(observation_id: str, c=Depends(container)) -> Response:
    try:
        src = c.explain_answer.crop_source(observation_id)
    except EvidenceError as e:
        raise HTTPException(404, {"error": "not_found", "detail": e.message}) from e
    image = Image.open(io.BytesIO(src.jpeg))
    x1, y1, x2, y2 = src.box
    mx, my = (x2 - x1) * MARGIN, (y2 - y1) * MARGIN
    box = (max(0, int(x1 - mx)), max(0, int(y1 - my)), min(image.width, int(x2 + mx)), min(image.height, int(y2 + my)))
    out = io.BytesIO()
    image.crop(box).convert("RGB").save(out, "JPEG", quality=85)
    return Response(out.getvalue(), media_type="image/jpeg")
