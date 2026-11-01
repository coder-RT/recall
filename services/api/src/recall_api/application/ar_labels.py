"""Everything Recall found in one room, placed in that room's saved AR map, so the phone can float a label over each
thing in the camera view. Positions go from the home frame to the ARKit frame of the room's newest processed scan
(the scan whose room map the phone relocalises in), as guidance does for its arrow."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from recall_api.application.list_things import ListThings
from recall_api.domain.memory import ScanStatus
from recall_api.domain.ports import ScanRepository


class NoRoomScan(LookupError):
    pass


@dataclass(frozen=True)
class ArLabel:
    object_id: str
    title: str
    place: str
    confidence: float
    photos: int | None
    trusted: bool
    needs_review: bool
    position_arkit: tuple[float, float, float]


@dataclass(frozen=True)
class ArLabels:
    scan_id: str
    room: str
    floor_y_arkit: float | None
    labels: list[ArLabel]


class ArLabelsInRoom:
    def __init__(self, things: ListThings, scans: ScanRepository) -> None:
        self.things, self.scans = things, scans

    def __call__(self, home_id: str, room: str) -> ArLabels:
        done = [
            s
            for s in self.scans.list_for_home(home_id)
            if s.room == room and s.status == ScanStatus.PROCESSED and s.transform_to_home
        ]
        if not done:
            raise NoRoomScan(room)
        scan = max(done, key=lambda s: s.created_at)
        to_arkit = np.linalg.inv(np.array(scan.transform_to_home, dtype=float).reshape(4, 4))

        def arkit(x: float, y: float, z: float) -> tuple[float, float, float]:
            p = to_arkit @ np.array([x, y, z, 1.0])
            return (round(float(p[0]), 3), round(float(p[1]), 3), round(float(p[2]), 3))

        labels = []
        for v in self.things.all(home_id):
            if v.room != room:
                continue
            obj, at, rel = v.thing, v.where.position, v.relation
            where = (
                f"{(rel.kind or 'near').replace('_', ' ')} the {rel.landmark.label}" if rel.landmark else "in the room"
            )
            title = obj.corrections.name or " ".join(x for x in (obj.display_color(), obj.label) if x)
            labels.append(
                ArLabel(
                    obj.id,
                    title,
                    f"{where}, at {rel.band.value} height",
                    round(v.where.confidence, 3),
                    v.where.photos,
                    v.trusted,
                    v.needs_review,
                    arkit(at.x, at.y, at.z),
                )  # fmt: skip
            )
        return ArLabels(scan.id, room, arkit(0.0, 0.0, 0.0)[1], labels)
