"""The only writer of memory: a pipeline result becomes the room model, landmarks, objects and observations."""

from __future__ import annotations

from collections import defaultdict
from typing import Any

from recall_api.application.ports import Clock
from recall_api.domain.memory import (
    BBox,
    FurnitureFootprint,
    Landmark,
    Observation,
    Position,
    RoomModel,
    Scan,
    ScanStatus,
    TrackedObject,
    WallSegment,
)
from recall_api.domain.memory.matching import match_label
from recall_api.domain.ports import HomeRepository, ScanRepository, TrackedObjectRepository


class IngestError(Exception):
    def __init__(self, code: str, message: str, status: int = 409) -> None:
        super().__init__(message)
        self.code, self.status = code, status


def _pos(v: list[float]) -> Position:
    return Position(float(v[0]), float(v[1]), float(v[2]))


def _room(d: dict[str, Any]) -> RoomModel:
    return RoomModel(
        floor_polygon=tuple(tuple(p) for p in d["floor_polygon"]),
        walls=tuple(WallSegment(tuple(w["start"]), tuple(w["end"]), w["height_m"]) for w in d["walls"]),
        furniture=tuple(
            FurnitureFootprint(f["label"], tuple(tuple(p) for p in f["footprint"]), f["top_z"]) for f in d["furniture"]
        ),
        height_m=d["height_m"],
    )


def _inside(poly: tuple[tuple[float, float], ...], p: Position) -> bool:
    """Ray casting: is p (x, y) inside the floor polygon this scan covered?"""
    inside = False
    n = len(poly)
    for i in range(n):
        (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % n]
        if (y1 > p.y) != (y2 > p.y) and p.x < (x2 - x1) * (p.y - y1) / (y2 - y1) + x1:
            inside = not inside
    return inside


class IngestScan:
    def __init__(
        self, scans: ScanRepository, homes: HomeRepository, objects: TrackedObjectRepository, clock: Clock, new_id
    ) -> None:
        self.scans, self.homes, self.objects, self.clock, self.new_id = scans, homes, objects, clock, new_id

    def __call__(self, scan_id: str, result: dict[str, Any]) -> Scan:
        scan = self.scans.get(scan_id)
        if scan is None:
            raise IngestError("not_found", "No such scan.", 404)
        if scan.status not in (ScanStatus.PROCESSING, ScanStatus.UPLOADED):
            raise IngestError("not_processing", f"The scan is {scan.status.value}, not processing.")
        home = self.homes.get(scan.home_id)
        room = _room(result["room"])
        seen_at = scan.created_at
        report = {"same": 0, "moved": 0, "new": 0, "gone": 0, "out_of_view": 0}

        # landmarks: furniture from this scan replaces the same label within 0.5 m, others are added
        for t in result["landmarks"]:
            c = _pos(t["centroid"])
            lm = next((x for x in home.landmarks if x.label == t["label"] and x.centroid.distance_to(c) < 0.5), None)
            box = BBox(_pos(t["bbox_min"]), _pos(t["bbox_max"]))
            front = tuple(t["front_dir"]) if t.get("front_dir") else None
            if lm is None:
                home.landmarks.append(Landmark(self.new_id("lm"), t["label"], box, c, room=scan.room, front_dir=front))
            else:
                lm.bbox, lm.centroid, lm.room = box, c, scan.room
        home.room_model = room
        home.first_scan_id = home.first_scan_id or scan.id
        self.homes.save(home)

        # objects: match per label against what memory last saw
        remembered = [o for o in self.objects.list_for_home(home.id) if o.where() is not None]
        by_label: dict[str, list[dict]] = defaultdict(list)
        for t in result["objects"]:
            by_label[t["label"]].append(t)
        labels = set(by_label) | {o.label for o in remembered}
        for label in labels:
            olds = [o for o in remembered if o.label == label]
            news = by_label.get(label, [])
            matches = match_label(
                [o.where().position for o in olds],
                [_pos(t["centroid"]) for t in news],
                covered=lambda p: _inside(room.floor_polygon, p),
            )
            for m in matches:
                report[m.kind] += 1
                if m.kind in ("same", "moved"):
                    obj = olds[m.existing]
                    if m.kind == "moved":
                        for o in obj.observations:
                            o.stale = True  # the old place is history now
                    if m.kind == "moved":
                        obj.corrections.height_m = None  # the user's height was for the old place
                    obj.observations.append(self._observation(obj.id, scan.id, seen_at, news[m.detected]))
                    _appearance(obj, news[m.detected])
                    self.objects.save(obj)
                elif m.kind == "new":
                    obj = TrackedObject(self.new_id("obj"), home.id, label)
                    obj.observations.append(self._observation(obj.id, scan.id, seen_at, news[m.detected]))
                    _appearance(obj, news[m.detected])
                    self.objects.save(obj)
                elif m.kind == "gone":
                    obj = olds[m.existing]
                    for o in obj.observations:
                        o.stale = True
                    self.objects.save(obj)

        scan.status = ScanStatus.PROCESSED
        scan.object_count = len(result["objects"])
        scan.transform_to_home = tuple(result.get("transform_to_home") or ())
        scan.detail = ", ".join(f"{v} {k.replace('_', ' ')}" for k, v in report.items() if v)
        self.scans.save(scan)
        return scan

    def _observation(self, object_id: str, scan_id: str, seen_at, t: dict) -> Observation:
        return Observation(
            self.new_id("obs"),
            object_id,
            scan_id,
            seen_at,
            _pos(t["centroid"]),
            float(t["confidence"]),
            keyframe_index=t.get("keyframe_index"),
        )


def _appearance(obj: TrackedObject, t: dict) -> None:
    """Colour and size from the newest sighting; the user's own values live in corrections and stay."""
    if t.get("color"):
        obj.color = t["color"]
    if t.get("size_m"):
        obj.size_m = tuple(float(v) for v in t["size_m"])
