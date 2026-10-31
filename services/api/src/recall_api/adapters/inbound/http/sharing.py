"""Robot access from the phone: mapping only. The device key only: a robot can't turn its own access on."""

from __future__ import annotations

from fastapi import APIRouter, Depends

from .deps import container, require_device_key
from .models import Sharing, SharingUpdate

router = APIRouter(tags=["robots"], dependencies=[Depends(require_device_key)])


def _sharing(c) -> Sharing:
    base = c.settings.public_url.rstrip("/")
    return Sharing(
        robot_access=c.robot_access.on,
        a2a_url=f"{base}/a2a/home-memory",
        agent_card_url=f"{base}/a2a/home-memory/.well-known/agent-card.json",
        export_url=f"{base}/homes/{c.settings.home_id}/robot-export",
    )


@router.get("/sharing", response_model=Sharing)
def get_sharing(c=Depends(container)) -> Sharing:
    return _sharing(c)


@router.put("/sharing", response_model=Sharing)
def set_sharing(body: SharingUpdate, c=Depends(container)) -> Sharing:
    c.robot_access.turn(body.robot_access)
    return _sharing(c)
