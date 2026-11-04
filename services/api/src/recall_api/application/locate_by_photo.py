"""Where am I? One photo from the phone, matched against the scans' place indexes (classic features + PnP, no model).

It runs alongside ARKit's own relocalisation, never instead of it: the phone asks while ARKit hasn't recognised the
room yet and uses whichever answers first. It answers:
- the room the photo was taken in, when one room clearly wins (it may not be the room the thing is in);
- the camera's pose in the world of the room map the phone runs, when that room matched well enough;
- the room's biggest one-of-a-kind furniture. It isn't spoken: nobody can point at what they can't see, and the
  memory's boxes aren't reliable enough to say what the phone faces (5 of 7 real frames; 2026-11-04).
"""

from __future__ import annotations

import time
from collections import Counter
from dataclasses import dataclass

from recall_api.application.ports import PlaceMatch, PlaceMatcher, PlaceQuery
from recall_api.domain.memory import Scan, ScanStatus
from recall_api.domain.ports import HomeRepository, ScanRepository

ROOM_MIN_INLIERS = 30  # a room is named from this many RANSAC inliers…
ROOM_MARGIN = 1.5  # …and this many times the next room's
POSE_MIN_INLIERS = 30  # on real scans: 59% of photos from another session fix, 89% of those right (evals/results.md)
POSE_MAX_REPROJ_PX = 4.0
HINTS = 3


class LocateError(Exception):
    def __init__(self, message: str, code: str = "not_found", status: int = 404) -> None:
        super().__init__(message)
        self.code, self.status = code, status


@dataclass(frozen=True)
class PlaceFix:
    room: str | None  # None: no room clearly matched
    scan_id: str | None  # the scan whose world `pose` is in (the requested map's)
    score: int
    runner_up_room: str | None
    runner_up_score: int
    pose: tuple[float, ...] | None  # ARKit camera-to-world, column-major, in the requested map's world
    inliers: int
    reproj_px: float | None
    hint: list[str]
    ms: int


def index_key(scan: Scan) -> str:
    return f"{scan.folder}/episode/place_index.npz"


class LocateByPhoto:
    def __init__(self, homes: HomeRepository, scans: ScanRepository, matcher: PlaceMatcher) -> None:
        self.homes, self.scans, self.matcher = homes, scans, matcher

    def __call__(self, home_id: str, scan_id: str, query: PlaceQuery, room: str | None = None) -> PlaceFix:
        t0 = time.perf_counter()
        home = self.homes.get(home_id)
        current = self.scans.get(scan_id)
        if home is None or current is None or current.home_id != home_id:
            raise LocateError("No such home or scan.")
        processed = [s for s in self.scans.list_for_home(home_id) if s.status == ScanStatus.PROCESSED]
        # the map's own world: its scan, the scan it was recognised in, and every rescan recognised in either
        root = current.aligned_to or current.id
        family = {s.id: s for s in processed if root in (s.id, s.aligned_to)} | {current.id: current}
        others: dict[str, Scan] = {}
        for s in sorted(processed, key=lambda s: s.created_at, reverse=True):  # each other room's newest scan
            if s.room != current.room and s.room not in {o.room for o in others.values()}:
                others[s.id] = s
        candidates = {sid: index_key(s) for sid, s in (family | others).items()}
        matches = self.matcher.match(query, candidates)
        rooms = {**{sid: s.room for sid, s in family.items()}, **{sid: s.room for sid, s in others.items()}}

        best_by_room: dict[str, PlaceMatch] = {}
        for m in matches:
            r = rooms[m.scan_id]
            if r not in best_by_room or m.inliers > best_by_room[r].inliers:
                best_by_room[r] = m
        ranked = sorted(best_by_room.items(), key=lambda kv: -kv[1].inliers)
        top_room, top = ranked[0] if ranked else (None, None)
        second_room, second = ranked[1] if len(ranked) > 1 else (None, None)
        score = top.inliers if top else 0
        clear = score >= ROOM_MIN_INLIERS and score >= ROOM_MARGIN * (second.inliers if second else 0)
        named = top_room if clear else None

        # a pose only in the map's own world, and only when its room clearly won (two rooms alike: no pose)
        mine = max((m for m in matches if m.scan_id in family), key=lambda m: m.inliers, default=None)
        pose = None
        if (
            mine is not None
            and mine.pose is not None
            and mine.inliers >= POSE_MIN_INLIERS
            and (mine.reproj_px or 99) <= POSE_MAX_REPROJ_PX
            and named == current.room
        ):
            pose = mine.pose
        hint_room = named or room or current.room
        return PlaceFix(
            room=named,
            scan_id=current.id,
            score=score,
            runner_up_room=second_room,
            runner_up_score=second.inliers if second else 0,
            pose=pose,
            inliers=mine.inliers if mine else 0,
            reproj_px=mine.reproj_px if mine and pose else None,
            hint=hints([lm for lm in home.landmarks if lm.room in (hint_room, None)]),
            ms=round((time.perf_counter() - t0) * 1000),
        )


def hints(landmarks: list) -> list[str]:
    """What to point the phone at: one-of-a-kind furniture first (a TV, not one of six chairs), biggest first."""
    counts = Counter(lm.label for lm in landmarks)
    seen: set[str] = set()
    out = []

    def size(lm) -> float:
        lo, hi = lm.bbox.lo, lm.bbox.hi
        return (hi.x - lo.x) * (hi.y - lo.y) * max(hi.z - lo.z, 0.05)

    for lm in sorted(landmarks, key=lambda lm: (counts[lm.label] > 1, -size(lm))):
        if lm.label in seen or lm.label == "door":
            continue
        seen.add(lm.label)
        out.append(lm.label)
        if len(out) == HINTS:
            break
    return out
