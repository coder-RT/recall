"""The robot export: mapping only. Off unless the owner turns robot access on; read-only; the robot key."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, Response

from recall_api.application.export_for_robot import RobotExportError

from .deps import caller, container, require_robot_or_device_key
from .models import RobotExport

router = APIRouter(tags=["robots"], dependencies=[Depends(require_robot_or_device_key)])


@router.get("/homes/{home_id}/robot-export", response_model=RobotExport)
def get_robot_export(home_id: str, request: Request, room: str | None = None, c=Depends(container)) -> RobotExport:
    share = c.share_robot_export
    return RobotExport.model_validate(share.document(_export(c, request, home_id, room, "json")))


@router.get("/homes/{home_id}/robot-package", response_class=Response)
def get_robot_package(home_id: str, request: Request, room: str | None = None, c=Depends(container)) -> Response:
    name, data = c.share_robot_export.package(_export(c, request, home_id, room, "zip"))
    return Response(data, media_type="application/zip",
                    headers={"Content-Disposition": f'attachment; filename="{name}"'})  # fmt: skip


def _export(c, request: Request, home_id: str, room: str | None, form: str):
    try:
        return c.share_robot_export(home_id, room, caller(request), form)
    except RobotExportError as e:
        raise HTTPException(e.status, {"error": e.code, "detail": str(e)}) from e
