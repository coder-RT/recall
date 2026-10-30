"""The remembered room model and objects: mapping only."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response

from recall_api.application.correct_object import CorrectionError, CorrectionInput
from recall_api.domain.memory import Home, TrackedObject
from recall_api.domain.spatial import relate, shelf_level

from .deps import container, require_device_key
from .models import ObjectCorrection, ObjectLocation, RoomModel

REVIEW_BELOW = 0.7  # confidence under this asks the user to check

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


def _location(obj: TrackedObject, home: Home) -> ObjectLocation | None:
    where = obj.where()
    if where is None:
        return None
    rel = relate(where.position, home.landmarks)
    shelves = [lm.bbox.top_z for lm in home.landmarks if lm.label == "shelf" and rel.landmark is lm]
    c = obj.corrections
    return ObjectLocation(
        object_id=obj.id,
        label=obj.label,
        position=list(where.position.as_tuple()),
        height_band=rel.band.value,
        room=rel.landmark.room if rel.landmark else None,
        landmark=rel.landmark.label if rel.landmark else None,
        relation=rel.kind,
        shelf_level=shelf_level(where.position.z, shelves) if shelves else None,
        seen_at=where.seen_at,
        confidence=where.confidence,
        stale=False,
        color=obj.display_color(),
        size_m=list(obj.size_m) if obj.size_m else None,
        corrections=ObjectCorrection(
            name=c.name, color=c.color, height_m=c.height_m, note=c.note, confirmed=c.confirmed
        ),
        needs_review=not c.confirmed and where.confidence < REVIEW_BELOW,
    )


def _home(c, home_id: str) -> Home:
    home = c.homes.get(home_id)
    if home is None:
        raise HTTPException(404, {"error": "not_found", "detail": "No such home."})
    return home


@router.get("/homes/{home_id}/objects", response_model=list[ObjectLocation])
def list_objects(home_id: str, c=Depends(container)) -> list[ObjectLocation]:
    home = _home(c, home_id)
    return [loc for obj in c.objects.list_for_home(home_id) if (loc := _location(obj, home))]


@router.patch("/homes/{home_id}/objects/{object_id}", response_model=ObjectLocation)
def correct_object(home_id: str, object_id: str, body: ObjectCorrection, c=Depends(container)) -> ObjectLocation:
    home = _home(c, home_id)
    sent = {k: getattr(body, k) for k in body.model_fields_set}
    if "color" in sent and sent["color"] is not None:
        sent["color"] = sent["color"].value
    try:
        obj = c.correct_object.update(home_id, object_id, CorrectionInput(**sent))
    except CorrectionError as e:
        raise HTTPException(e.status, {"error": e.code, "detail": e.message}) from e
    loc = _location(obj, home)
    if loc is None:
        raise HTTPException(404, {"error": "not_found", "detail": "This object has no sighting left."})
    return loc


@router.delete("/homes/{home_id}/objects/{object_id}", status_code=204)
def remove_object(home_id: str, object_id: str, c=Depends(container)) -> Response:
    _home(c, home_id)
    try:
        c.correct_object.remove(home_id, object_id)
    except CorrectionError as e:
        raise HTTPException(e.status, {"error": e.code, "detail": e.message}) from e
    return Response(status_code=204)
