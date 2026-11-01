"""The remembered room model and objects: mapping only."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response

from recall_api.application.correct_object import CorrectionError, CorrectionInput
from recall_api.application.export_for_robot import RobotExportError
from recall_api.application.list_things import NoSuchHome, ThingView
from recall_api.domain.memory import Home, Trust

from .deps import container, require_device_key
from .models import ObjectCorrection, ObjectLocation, RobotExport, RoomModel, TrustUpdate
from .models import Trust as TrustLevel
from .robots import export_document

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
        north_deg=r.north_deg,
    )


@router.get("/homes/{home_id}/room-map", response_model=RobotExport)
def get_room_map(home_id: str, room: str | None = None, c=Depends(container)) -> RobotExport:
    # the owner looking at their own home: no robot switch, and not recorded as a robot export
    try:
        return export_document(c.export_for_robot(home_id, room))
    except RobotExportError as e:
        raise HTTPException(e.status, {"error": e.code, "detail": str(e)}) from e


def _location(v: ThingView) -> ObjectLocation:
    obj, where, c = v.thing, v.where, v.thing.corrections
    return ObjectLocation(
        object_id=obj.id,
        label=obj.label,
        position=list(where.position.as_tuple()),
        height_band=v.relation.band.value,
        room=v.room,
        landmark=v.relation.landmark.label if v.relation.landmark else None,
        relation=v.relation.kind,
        shelf_level=v.shelf_level,
        seen_at=where.seen_at,
        confidence=where.confidence,
        stale=False,
        color=obj.display_color(),
        size_m=list(obj.size_m) if obj.size_m else None,
        corrections=ObjectCorrection(
            name=c.name, color=c.color, height_m=c.height_m, note=c.note, confirmed=c.confirmed
        ),
        photos=where.photos,
        trusted=v.trusted,
        needs_review=v.needs_review,
    )


def _home(c, home_id: str) -> Home:
    try:
        return c.list_things.home(home_id)
    except NoSuchHome as e:
        raise HTTPException(404, {"error": "not_found", "detail": "No such home."}) from e


@router.get("/homes/{home_id}/objects", response_model=list[ObjectLocation])
def list_objects(home_id: str, c=Depends(container)) -> list[ObjectLocation]:
    _home(c, home_id)
    return [_location(v) for v in c.list_things.all(home_id)]


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
    view = c.list_things.view(home, obj)
    if view is None:
        raise HTTPException(404, {"error": "not_found", "detail": "This object has no sighting left."})
    return _location(view)


@router.delete("/homes/{home_id}/objects/{object_id}", status_code=204)
def remove_object(home_id: str, object_id: str, c=Depends(container)) -> Response:
    _home(c, home_id)
    try:
        c.correct_object.remove(home_id, object_id)
    except CorrectionError as e:
        raise HTTPException(e.status, {"error": e.code, "detail": e.message}) from e
    return Response(status_code=204)


@router.get("/trust", response_model=TrustLevel)
def get_trust(c=Depends(container)) -> TrustLevel:
    level = c.trust.level
    return TrustLevel(level=level.value, min_photos=level.min_photos)


@router.put("/trust", response_model=TrustLevel)
def set_trust(body: TrustUpdate, c=Depends(container)) -> TrustLevel:
    level = c.trust.set(Trust(body.level.value))
    return TrustLevel(level=level.value, min_photos=level.min_photos)
