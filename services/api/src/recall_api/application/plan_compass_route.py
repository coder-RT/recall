"""Directions for the Watch, which has a compass but no camera: from where the scan of the thing's room began (the
phone's first position, usually the doorway) to the thing, as legs of a magnetic bearing and metres. The route is the
same clearance-aware A* the phone's guidance uses; north is what the phone's compass measured while scanning."""

from __future__ import annotations

from dataclasses import dataclass

from recall_api.application import scan_geometry
from recall_api.application.ports import BlobStore
from recall_api.application.trust import TrustPolicy
from recall_api.domain.navigation import FloorGrid, NavConfig, NoSafePath, compass_legs, plan, simplify
from recall_api.domain.ports import HomeRepository, ScanRepository, TrackedObjectRepository
from recall_api.domain.spatial import relate


class CompassRouteError(Exception):
    def __init__(self, code: str, message: str, status: int = 409) -> None:
        super().__init__(message)
        self.code, self.status = code, status


@dataclass(frozen=True)
class CompassRoute:
    object_id: str
    label: str
    color: str | None
    start: str
    place: str
    legs: list[dict]


class PlanCompassRoute:
    def __init__(
        self,
        homes: HomeRepository,
        scans: ScanRepository,
        objects: TrackedObjectRepository,
        blobs: BlobStore,
        trust: TrustPolicy | None = None,
        cfg: NavConfig | None = None,
    ) -> None:
        self.homes, self.scans, self.objects, self.blobs = homes, scans, objects, blobs
        self.trust, self.cfg = trust or TrustPolicy(), cfg or NavConfig()

    def __call__(self, home_id: str, object_id: str) -> CompassRoute:
        home = self.homes.get(home_id)
        obj = self.objects.get(object_id)
        where = obj.where(self.trust.level) if obj and obj.home_id == home_id else None
        if home is None or where is None:
            raise CompassRouteError("not_found", "That thing isn't in this home's memory.", 404)
        north = home.room_model.north_deg if home.room_model else None
        if north is None:
            raise CompassRouteError("no_compass", "This room was scanned without a reliable compass; scan it again.")
        scan = self.scans.get(where.scan_id)
        cloud = scan_geometry.cloud(self.blobs, scan) if scan else None
        walked = scan_geometry.walked(self.blobs, scan) if scan else None
        if cloud is None or walked is None or not len(walked):
            raise CompassRouteError("no_cloud", "The scan's geometry is missing; process the scan again.")
        start = (float(walked[0][0]), float(walked[0][1]))  # where the phone was when the scan began
        grid = FloorGrid.from_points(cloud, self.cfg, walked=walked)
        try:
            path = plan(grid, start, (where.position.x, where.position.y), self.cfg)
        except NoSafePath as e:
            raise CompassRouteError("no_path", f"No clear way for a person: {e}.") from e
        legs = compass_legs(simplify(path), north)
        if not legs:  # already within reach of the start
            legs = [{"bearing_deg": 0.0, "metres": 0.0}]
        rel = relate(where.position, home.landmarks)
        at = f"{(rel.kind or 'near').replace('_', ' ')} the {rel.landmark.label}" if rel.landmark else "in the room"
        return CompassRoute(
            object_id=obj.id,
            label=obj.corrections.name or obj.label,
            color=obj.display_color(),
            start=f"where you started the scan of {scan.room}",
            place=f"{at}, at {rel.band.value} height",
            legs=legs,
        )
