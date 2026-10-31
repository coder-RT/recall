"""Live guidance: the phone's relocalised ARKit pose → home frame → a clearance-aware route as clock-face steps."""

from __future__ import annotations

import io
import json
import math
from dataclasses import dataclass
from typing import Any

import numpy as np

from recall_api.application.ports import BlobStore
from recall_api.domain.memory import Scan
from recall_api.domain.navigation import FloorGrid, NavConfig, NoSafePath, plan, simplify, to_clock_steps
from recall_api.domain.ports import HomeRepository, ScanRepository, TrackedObjectRepository
from recall_api.domain.spatial import relate


class GuidanceError(Exception):
    def __init__(self, code: str, message: str, status: int = 404) -> None:
        super().__init__(message)
        self.code, self.status = code, status


@dataclass
class Session:
    id: str
    home_id: str
    object_id: str
    position: np.ndarray  # home frame
    heading: np.ndarray  # unit (x, y), home frame
    tracking: str


def _bearing(room, x: float, y: float) -> float | None:
    """Compass bearing (magnetic, clockwise from north) from the room's centre to (x, y), when north is known."""
    if room is None or room.north_deg is None or not room.floor_polygon:
        return None
    cx = sum(p[0] for p in room.floor_polygon) / len(room.floor_polygon)
    cy = sum(p[1] for p in room.floor_polygon) / len(room.floor_polygon)
    if abs(x - cx) + abs(y - cy) < 1e-6:
        return None
    return round((math.degrees(math.atan2(x - cx, y - cy)) - room.north_deg) % 360, 1)


class PlanGuidance:
    def __init__(
        self,
        homes: HomeRepository,
        scans: ScanRepository,
        objects: TrackedObjectRepository,
        blobs: BlobStore,
        new_id,
        cfg: NavConfig | None = None,
    ) -> None:
        self.homes, self.scans, self.objects, self.blobs, self.new_id = homes, scans, objects, blobs, new_id
        self.cfg = cfg or NavConfig()
        self.sessions: dict[str, Session] = {}
        self._grids: dict[str, tuple[str, FloorGrid]] = {}

    def _transform(self, home_id: str) -> tuple[np.ndarray, Scan]:
        home = self.homes.get(home_id)
        if home is None or home.first_scan_id is None:
            raise GuidanceError("no_scan", "This home has no processed scan yet.")
        scan = self.scans.get(home.first_scan_id)
        if scan is None or not scan.transform_to_home:
            raise GuidanceError("no_transform", "The scan has no frame alignment yet.")
        return np.array(scan.transform_to_home, dtype=float).reshape(4, 4), scan

    def _grid(self, home_id: str, scan: Scan) -> FloorGrid:
        cached = self._grids.get(home_id)
        if cached and cached[0] == scan.id:
            return cached[1]
        key = f"{scan.folder}/episode/home_cloud.npy"
        if not self.blobs.exists(key):
            raise GuidanceError("no_cloud", "The scan's point cloud is missing; process the scan again.")
        cloud = np.load(io.BytesIO(self.blobs.get(key))).astype(np.float64)
        grid = FloorGrid.from_points(cloud, self.cfg, walked=self._walked(scan))
        self._grids[home_id] = (scan.id, grid)
        return grid

    def _walked(self, scan: Scan) -> np.ndarray | None:
        """The phone's floor positions during the scan (home frame), from the episode's poses.jsonl."""
        key = f"{scan.folder}/episode/poses.jsonl"
        if not self.blobs.exists(key) or not scan.transform_to_home:
            return None
        T = np.array(scan.transform_to_home, dtype=float).reshape(4, 4)
        xy = []
        for line in self.blobs.get(key).decode().splitlines():
            if not line.strip():
                continue
            M = np.array(json.loads(line)["pose"], dtype=float).reshape(4, 4).T  # column-major
            xy.append((T @ np.append(M[:3, 3], 1.0))[:2])
        return np.array(xy) if xy else None

    def start(self, home_id: str, object_id: str, pose_column_major: list[float], tracking: str) -> dict[str, Any]:
        T, scan = self._transform(home_id)
        M = np.array(pose_column_major, dtype=float).reshape(4, 4).T  # ARKit cam-to-world
        pos = (T @ np.append(M[:3, 3], 1.0))[:3]
        fwd = T[:3, :3] @ (-M[:3, 2])  # the camera looks along −Z
        heading = fwd[:2] / (np.linalg.norm(fwd[:2]) or 1.0)
        obj = self.objects.get(object_id)
        last = obj.where() if obj else None
        if last is None:
            raise GuidanceError("object_not_seen", "That object isn't in memory.")
        session = Session(self.new_id("gs"), home_id, object_id, pos, heading, tracking)
        self.sessions[session.id] = session
        home = self.homes.get(home_id)
        rel = relate(last.position, home.landmarks)
        where = (
            f"{rel.kind.replace('_', ' ')} the {rel.landmark.label}"
            if rel.landmark and rel.kind != "near"
            else f"near the {rel.landmark.label}"
            if rel.landmark
            else "in the room"
        )
        arrive = f"Your {obj.label} should be in front of you, {where}, at {rel.band.value} height."
        # where to draw the arrow in the phone's camera view, and the compass bearing for landmark directions
        target = (np.linalg.inv(T) @ np.array([last.position.x, last.position.y, last.position.z, 1.0]))[:3]
        # the floor's height in the phone's world (under the person and under the thing), for the arrows on the floor
        floor_y = np.mean(
            [
                (np.linalg.inv(T) @ np.array([x, y, 0.0, 1.0]))[1]
                for x, y in ((pos[0], pos[1]), (last.position.x, last.position.y))
            ]
        )
        base = {
            "session_id": session.id,
            "object_label": obj.label,
            "arrive_say": arrive,
            "target_arkit": [round(float(v), 3) for v in target],
            "floor_y_arkit": round(float(floor_y), 3),
            "bearing_deg": _bearing(home.room_model, last.position.x, last.position.y),
        }
        if tracking != "normal":
            return {
                **base,
                "mode": "landmarks",
                "reason": "tracking is limited, so only landmark directions",
                "steps": [{"clock": 12, "metres": 0, "say": f"Your {obj.label} is {where}."}],
                "path": [],
                "path_arkit": [],
            }
        try:
            path = plan(self._grid(home_id, scan), (pos[0], pos[1]), (last.position.x, last.position.y), self.cfg)
        except NoSafePath as e:
            return {
                **base,
                "mode": "landmarks",
                "reason": str(e),
                "steps": [
                    {"clock": 12, "metres": 0, "say": f"I can't find a clear path. Your {obj.label} is {where}."}
                ],
                "path": [],
                "path_arkit": [],
            }
        waypoints = simplify(path)
        Tinv = np.linalg.inv(T)
        arkit = [(Tinv @ np.array([x, y, 0.0, 1.0]))[[0, 2]] for x, y in waypoints]
        return {
            **base,
            "mode": "route",
            "reason": None,
            "steps": to_clock_steps(waypoints, (heading[0], heading[1])),
            "path": [[round(x, 3), round(y, 3)] for x, y in waypoints],
            "path_arkit": [[round(float(a), 3), round(float(b), 3)] for a, b in arkit],
        }

    def localize(self, session_id: str) -> dict[str, Any]:
        s = self.sessions.get(session_id)
        if s is None:
            return {"result": "unknown_session"}
        return {
            "position": np.round(s.position, 2).tolist(),
            "facing": np.round(s.heading, 2).tolist(),
            "tracking_state": s.tracking,
        }

    def plan_for_agent(self, session_id: str, object_id: str) -> dict[str, Any]:
        s = self.sessions.get(session_id)
        if s is None:
            return {"result": "unknown_session"}
        T, _ = self._transform(s.home_id)
        M = np.eye(4)
        M[:3, 3] = (np.linalg.inv(T) @ np.append(s.position, 1.0))[:3]
        M[:3, 2] = -(np.linalg.inv(T)[:3, :3] @ np.append(s.heading, 0.0))
        g = self.start(s.home_id, object_id, M.T.reshape(-1).tolist(), s.tracking)
        return {"mode": g["mode"], "steps": [{"clock": x["clock"], "metres": x["metres"]} for x in g["steps"]]}
