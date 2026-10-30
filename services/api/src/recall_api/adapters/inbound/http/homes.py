"""The remembered room model and objects: mapping only."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from recall_api.domain.spatial import relate, shelf_level

from .deps import container, require_device_key
from .models import ObjectLocation, RoomModel

router = APIRouter(tags=["homes"], dependencies=[Depends(require_device_key)])


@router.get("/homes/{home_id}/room", response_model=RoomModel)
def get_room(home_id: str, c=Depends(container)) -> RoomModel:
    home = c.homes.get(home_id)
    if home is None or home.room_model is None:
        raise HTTPException(404, {"error": "not_found", "detail": "No processed scan for this home yet."})
    r = home.room_model
    return RoomModel(
        floor_polygon=[list(p) for p in r.floor_polygon],
        walls=[{"start": list(w.start), "end": list(w.end), "height_m": w.height_m} for w in r.walls],
        furniture=[
            {"label": f.label, "footprint": [list(p) for p in f.footprint], "top_z": f.top_z} for f in r.furniture
        ],
        height_m=r.height_m,
    )


@router.get("/homes/{home_id}/objects", response_model=list[ObjectLocation])
def list_objects(home_id: str, c=Depends(container)) -> list[ObjectLocation]:
    home = c.homes.get(home_id)
    if home is None:
        raise HTTPException(404, {"error": "not_found", "detail": "No such home."})
    out = []
    for obj in c.objects.list_for_home(home_id):
        last = obj.last_seen()
        if last is None:
            continue
        rel = relate(last.position, home.landmarks)
        shelves = [lm.bbox.top_z for lm in home.landmarks if lm.label == "shelf" and rel.landmark is lm]
        out.append(
            ObjectLocation(
                object_id=obj.id,
                label=obj.label,
                position=list(last.position.as_tuple()),
                height_band=rel.band.value,
                room=rel.landmark.room if rel.landmark else None,
                landmark=rel.landmark.label if rel.landmark else None,
                relation=rel.kind,
                shelf_level=shelf_level(last.position.z, shelves) if shelves else None,
                seen_at=last.seen_at,
                confidence=last.confidence,
                stale=False,
            )
        )
    return out
