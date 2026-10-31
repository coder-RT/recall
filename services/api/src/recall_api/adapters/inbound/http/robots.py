"""The robot export: mapping only. Off unless the owner turns robot access on; read-only; the robot key."""

from __future__ import annotations

import base64
import hmac

from fastapi import APIRouter, Depends, HTTPException, Request

from recall_api.adapters.outbound.export.robot_files import document
from recall_api.application.export_for_robot import RobotExportError

from .deps import container, require_robot_or_device_key
from .models import RobotExport

router = APIRouter(tags=["robots"], dependencies=[Depends(require_robot_or_device_key)])


@router.get("/homes/{home_id}/robot-export", response_model=RobotExport)
def get_robot_export(home_id: str, request: Request, room: str | None = None, c=Depends(container)) -> RobotExport:
    # the switch is about robots: the owner (device key) can always export their own map to share it
    got = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    owner = c.settings.device_key is not None and hmac.compare_digest(got, c.settings.device_key.get_secret_value())
    if not (owner or c.robot_access.export_open):
        raise HTTPException(403, {"error": "robot_access_off", "detail": "Robot access is off. Turn it on in the app."})
    try:
        e = c.export_for_robot(home_id, room)
    except RobotExportError as err:
        raise HTTPException(err.status, {"error": err.code, "detail": str(err)}) from err
    w, h = e.map.size
    m = {**e.map.yaml_fields("map.pgm"), "width": w, "height": h, "pgm_base64": base64.b64encode(e.map.pgm()).decode()}
    return RobotExport.model_validate({**document(e), "map": m, "room_model": e.room_model})
