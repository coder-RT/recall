"""The robot export: mapping only. Off unless the owner turns robot access on; read-only; the robot key."""

from __future__ import annotations

import base64

from fastapi import APIRouter, Depends, HTTPException, Request, Response

from recall_api.adapters.outbound.export.robot_files import document, package
from recall_api.application.export_for_robot import RobotExportError
from recall_api.domain.audit import Action, Actor, Outcome

from .deps import caller, container, require_robot_or_device_key
from .models import RobotExport

router = APIRouter(tags=["robots"], dependencies=[Depends(require_robot_or_device_key)])


@router.get("/homes/{home_id}/robot-export", response_model=RobotExport)
def get_robot_export(home_id: str, request: Request, room: str | None = None, c=Depends(container)) -> RobotExport:
    return export_document(_export(c, request, home_id, room, "json"))


@router.get("/homes/{home_id}/robot-package", response_class=Response)
def get_robot_package(home_id: str, request: Request, room: str | None = None, c=Depends(container)) -> Response:
    e = _export(c, request, home_id, room, "zip")
    name = "recall-" + "".join(ch if ch.isalnum() else "-" for ch in e.room.lower()).strip("-") + ".zip"
    return Response(package(e), media_type="application/zip",
                    headers={"Content-Disposition": f'attachment; filename="{name}"'})  # fmt: skip


def _export(c, request: Request, home_id: str, room: str | None, form: str):
    """The room's export, if the caller may have it; every outcome is recorded."""
    # the switch is about robots: the owner (device key) can always export their own map to share it
    who = caller(request)
    if not (who == Actor.OWNER or c.robot_access.export_open):
        c.auditor(Action.ROBOT_EXPORT_READ, who, Outcome.REFUSED, target_type="home", target_id=home_id,
                  why="access off", form=form)  # fmt: skip
        raise HTTPException(403, {"error": "robot_access_off", "detail": "Robot access is off. Turn it on in the app."})
    try:
        e = c.export_for_robot(home_id, room)
    except RobotExportError as err:
        c.auditor(Action.ROBOT_EXPORT_READ, who, Outcome.FAILED, target_type="home", target_id=home_id, why=err.code,
                  form=form)  # fmt: skip
        raise HTTPException(err.status, {"error": err.code, "detail": str(err)}) from err
    c.auditor(Action.ROBOT_EXPORT_READ, who, target_type="home", target_id=home_id, room=e.room,
              things=len(e.objects), scan_id=e.scan_id, form=form)  # fmt: skip
    return e


def export_document(e) -> RobotExport:
    """The export as JSON: the robot's document, the map inline (PGM as base64) and the room outline."""
    w, h = e.map.size
    m = {**e.map.yaml_fields("map.pgm"), "width": w, "height": h, "pgm_base64": base64.b64encode(e.map.pgm()).decode()}
    return RobotExport.model_validate({**document(e), "map": m, "room_model": e.room_model})
