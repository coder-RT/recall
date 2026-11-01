"""Guidance routes: mapping only."""

from __future__ import annotations

import json

import numpy as np
from fastapi import APIRouter, Depends, Form, HTTPException, UploadFile

from recall_api.application.plan_guidance import GuidanceError
from recall_api.domain.spatial import CameraView

from .deps import container, require_device_key
from .models import GuidanceRequest, GuidanceSession, VerificationResult

router = APIRouter(tags=["guidance"], dependencies=[Depends(require_device_key)])


@router.post("/guidance/sessions", response_model=GuidanceSession)
def start_guidance(body: GuidanceRequest, c=Depends(container)) -> GuidanceSession:
    try:
        g = c.guidance.start(body.home_id, body.object_id, list(body.pose.matrix), body.tracking.value)
    except GuidanceError as e:
        raise HTTPException(e.status, {"error": e.code, "detail": str(e)}) from e
    return GuidanceSession.model_validate(g)


def _view(pose: str, depth: bytes) -> CameraView:
    """The multipart form as a camera view: pose JSON (ARKit, column-major) and raw 16-bit depth in millimetres."""
    try:
        p = json.loads(pose)
        M = np.array(p["pose"], dtype=float).reshape(4, 4).T
        k = p["intrinsics"]
        dw, dh = (int(v) for v in p["depth_size"])
        mm = np.frombuffer(depth, "<u2")
        if mm.size != dw * dh:
            raise ValueError(f"depth has {mm.size} values, depth_size says {dw} x {dh}")
        iw, ih = (int(v) for v in p["image_size"])
        return CameraView(M, float(k["fx"]), float(k["fy"]), float(k["cx"]), float(k["cy"]), (iw, ih),
                          mm.reshape(dh, dw).astype(float) / 1000.0)  # fmt: skip
    except (KeyError, ValueError, TypeError) as e:
        # a fixed sentence: the parser's own message would echo the request back
        detail = "Bad arrival frame: pose, intrinsics, sizes and depth must match."
        raise HTTPException(422, {"error": "invalid", "detail": detail}) from e


@router.post("/guidance/sessions/{session_id}/verify", response_model=VerificationResult)
async def verify(
    session_id: str, image: UploadFile, depth: UploadFile, pose: str = Form(...), c=Depends(container)
) -> VerificationResult:
    view = _view(pose, await depth.read())
    try:
        v = c.arrival_verifier(session_id, await image.read(), view)
    except GuidanceError as e:
        raise HTTPException(e.status, {"error": e.code, "detail": str(e)}) from e
    return VerificationResult(outcome=v.outcome, say=v.say, distance_cm=v.distance_cm, sam_score=v.sam_score,
                              position=v.position)  # fmt: skip
