"""The robot export: one room's memory as a robot's navigation stack reads it. Geometry and labels only: the map,
where things and furniture are, the room's outline and a coarse point cloud. Never photos, frames, colours sampled
from photos beyond a colour word, the user's own names or notes, or anyone's live position.

Each room has its own frame (rooms are scanned separately), so an export is one room: the newest processed scan's.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

import numpy as np

from recall_api.application import scan_geometry
from recall_api.application.ports import BlobStore, Clock
from recall_api.application.trust import TrustPolicy
from recall_api.domain.memory import ScanStatus, TrackedObject, Trust
from recall_api.domain.navigation import NavConfig, OccupancyMap
from recall_api.domain.ports import HomeRepository, ScanRepository, TrackedObjectRepository

FRAME = "map"  # the home frame: metres, z up, floor at z = 0
IDENTITY = [0.0, 0.0, 0.0, 1.0]  # x, y, z, w: things have a place but no measured heading


class RobotExportError(Exception):
    def __init__(self, code: str, message: str, status: int = 404) -> None:
        super().__init__(message)
        self.code, self.status = code, status


@dataclass
class RobotExport:
    home_id: str
    room: str
    scan_id: str
    generated_at: datetime
    map: OccupancyMap
    objects: list[dict]
    landmarks: list[dict]
    room_model: dict
    cloud: np.ndarray = field(repr=False)  # (N, 3) voxel-downsampled points, home frame


def voxel_downsample(points: np.ndarray, size: float) -> np.ndarray:
    """One point per `size` cube: the mean of the points inside it."""
    if len(points) == 0:
        return points.reshape(0, 3)
    keys = np.floor(points / size).astype(np.int64)
    _, inverse, counts = np.unique(keys, axis=0, return_inverse=True, return_counts=True)
    sums = np.zeros((len(counts), 3))
    np.add.at(sums, inverse.ravel(), points)
    return sums / counts[:, None]


class ExportForRobot:
    def __init__(
        self,
        homes: HomeRepository,
        scans: ScanRepository,
        objects: TrackedObjectRepository,
        blobs: BlobStore,
        clock: Clock,
        cfg: NavConfig | None = None,
        voxel_m: float = 0.05,
        trust: TrustPolicy | None = None,
    ) -> None:
        self.homes, self.scans, self.objects, self.blobs, self.clock = homes, scans, objects, blobs, clock
        self.cfg, self.voxel_m, self.trust = cfg or NavConfig(), voxel_m, trust or TrustPolicy()

    def __call__(self, home_id: str, room: str | None = None) -> RobotExport:
        home = self.homes.get(home_id)
        if home is None:
            raise RobotExportError("not_found", "No such home.")
        done = [
            s
            for s in self.scans.list_for_home(home_id)
            if s.status == ScanStatus.PROCESSED and (room is None or s.room == room)
        ]
        if not done:
            raise RobotExportError("no_scan", "No processed scan to export yet.")
        scan = max(done, key=lambda s: s.created_at)
        cloud = scan_geometry.cloud(self.blobs, scan)
        if cloud is None or home.room_model is None:
            raise RobotExportError("no_cloud", "The scan's point cloud is missing; process the scan again.", 409)
        occupancy = OccupancyMap.from_points(cloud, scan_geometry.walked(self.blobs, scan), self.cfg)
        rooms: dict[str, str | None] = {}

        def room_of(o: TrackedObject) -> str | None:
            sid = o.where().scan_id
            if sid not in rooms:
                s = self.scans.get(sid)
                rooms[sid] = s.room if s else None
            return rooms[sid]

        level = self.trust.level  # robots and the owner's map show only what the owner's level trusts
        things = [
            o for o in self.objects.list_for_home(home_id) if o.where(level) is not None and room_of(o) == scan.room
        ]
        return RobotExport(
            home_id=home_id,
            room=scan.room,
            scan_id=scan.id,
            generated_at=self.clock.now(),
            map=occupancy,
            objects=[_object(o, level) for o in sorted(things, key=lambda o: o.id)],
            landmarks=[_landmark(lm) for lm in home.landmarks if lm.room == scan.room],
            room_model=home.room_model.to_dict(),
            cloud=voxel_downsample(cloud, self.voxel_m),
        )


def _object(o: TrackedObject, level: Trust) -> dict:
    w = o.where(level)
    return {
        "id": o.id,
        "label": o.label,
        "aliases": sorted(set(o.aliases)),  # the scan's words only; the user's own names stay on the Mac
        "color": o.display_color(),
        "position": [round(w.position.x, 3), round(w.position.y, 3), round(w.position.z, 3)],
        "orientation": IDENTITY,
        "frame_id": FRAME,
        "size_m": [round(v, 3) for v in o.size_m] if o.size_m else None,
        "last_seen": w.seen_at.isoformat(),
        "confidence": round(w.confidence, 3),
    }


def _landmark(lm) -> dict:
    return {
        "id": lm.id,
        "label": lm.label,
        "centroid": [round(v, 3) for v in lm.centroid.as_tuple()],
        "bbox_min": [round(v, 3) for v in lm.bbox.lo.as_tuple()],
        "bbox_max": [round(v, 3) for v in lm.bbox.hi.as_tuple()],
        "front_dir": list(lm.front_dir) if lm.front_dir else None,
        "frame_id": FRAME,
    }
