"""Entities and value objects of the memory. Home frame: metres, floor z = 0, z up."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime
from enum import StrEnum


@dataclass(frozen=True)
class Position:
    x: float
    y: float
    z: float

    def distance_to(self, other: Position) -> float:
        return math.dist((self.x, self.y, self.z), (other.x, other.y, other.z))

    def as_tuple(self) -> tuple[float, float, float]:
        return (self.x, self.y, self.z)


@dataclass(frozen=True)
class Pose:
    """ARKit camera-to-world, column-major 4x4 as 16 numbers."""

    matrix: tuple[float, ...]

    def __post_init__(self) -> None:
        if len(self.matrix) != 16:
            raise ValueError("a pose has 16 numbers")

    @property
    def position(self) -> Position:
        m = self.matrix  # column-major: translation is elements 12, 13, 14
        return Position(m[12], m[13], m[14])

    @property
    def forward_xy(self) -> tuple[float, float]:
        """Unit heading on the floor plane; ARKit's camera looks along −Z (third column)."""
        fx, fy = -self.matrix[8], -self.matrix[9]
        n = math.hypot(fx, fy) or 1.0
        return (fx / n, fy / n)


@dataclass(frozen=True)
class BBox:
    lo: Position
    hi: Position

    @property
    def top_z(self) -> float:
        return self.hi.z

    def contains_xy(self, p: Position, margin: float = 0.0) -> bool:
        return self.lo.x - margin <= p.x <= self.hi.x + margin and self.lo.y - margin <= p.y <= self.hi.y + margin


@dataclass(frozen=True)
class WallSegment:
    start: tuple[float, float]
    end: tuple[float, float]
    height_m: float


@dataclass(frozen=True)
class FurnitureFootprint:
    label: str
    footprint: tuple[tuple[float, float], ...]
    top_z: float


@dataclass(frozen=True)
class RoomModel:
    floor_polygon: tuple[tuple[float, float], ...]
    walls: tuple[WallSegment, ...]
    furniture: tuple[FurnitureFootprint, ...]
    height_m: float
    # magnetic north in the home frame, degrees clockwise from +y (None without a reliable compass)
    north_deg: float | None = None

    @staticmethod
    def from_dict(d: dict) -> RoomModel:
        """room.json (schemas/RoomModel.yaml) as the domain value."""
        return RoomModel(
            floor_polygon=tuple(tuple(p) for p in d["floor_polygon"]),
            walls=tuple(WallSegment(tuple(w["start"]), tuple(w["end"]), w["height_m"]) for w in d["walls"]),
            furniture=tuple(
                FurnitureFootprint(f["label"], tuple(tuple(p) for p in f["footprint"]), f["top_z"])
                for f in d["furniture"]
            ),
            height_m=d["height_m"],
            north_deg=d.get("north_deg"),
        )

    def to_dict(self) -> dict:
        return {
            "floor_polygon": [list(p) for p in self.floor_polygon],
            "walls": [{"start": list(w.start), "end": list(w.end), "height_m": w.height_m} for w in self.walls],
            "furniture": [
                {"label": f.label, "footprint": [list(p) for p in f.footprint], "top_z": f.top_z}
                for f in self.furniture
            ],
            "height_m": self.height_m,
            "north_deg": self.north_deg,
        }


@dataclass
class Landmark:
    id: str
    label: str
    bbox: BBox
    centroid: Position
    room: str | None = None
    front_dir: tuple[float, float] | None = None


@dataclass
class Observation:
    id: str
    object_id: str
    scan_id: str
    seen_at: datetime
    position: Position
    confidence: float
    keyframe_index: int | None = None
    stale: bool = False


@dataclass
class TrackedObject:
    """Aggregate: one thing in the home and every time it was seen."""

    id: str
    home_id: str
    label: str
    aliases: tuple[str, ...] = ()
    observations: list[Observation] = field(default_factory=list)
    color: str | None = None  # a basic colour name, from the photo or from the user
    size_m: tuple[float, float, float] | None = None  # bounding box (x, y, z) from the newest sighting
    corrections: Corrections = field(default_factory=lambda: Corrections())

    def last_seen(self, min_confidence: float = 0.5) -> Observation | None:
        fresh = [o for o in self.observations if not o.stale and o.confidence >= min_confidence]
        return max(fresh, key=lambda o: o.seen_at, default=None)

    def where(self) -> Observation | None:
        """The newest sighting, with the user's height in place of the measured one when they gave it.
        A confirmed object counts as certain."""
        last = self.last_seen(0.0 if self.corrections.confirmed else 0.5)
        if last is None:
            return None
        c = self.corrections
        if c.height_m is not None:
            last = replace(last, position=Position(last.position.x, last.position.y, c.height_m))
        if c.confirmed:
            last = replace(last, confidence=1.0)
        return last

    def display_color(self) -> str | None:
        return self.corrections.color or self.color

    def matches(self, name: str) -> bool:
        words = name.strip().lower().split()
        colors = [w for w in words if w in COLOR_NAMES]
        if colors and self.display_color() not in colors:
            return False  # "the red bag" never matches a blue bag
        n = " ".join(w for w in words if w not in COLOR_NAMES) or name.strip().lower()
        names = {self.label.lower(), *(a.lower() for a in self.aliases)}
        if self.corrections.name:
            names.add(self.corrections.name.lower())
        singular = n[:-1] if n.endswith("s") else n
        return n in names or singular in names or any(singular in x or x in n for x in names if len(x) >= 3)


# the basic colour terms the pipeline names; a user can type any of these
COLOR_NAMES = (
    "black", "white", "grey", "red", "orange", "yellow", "green", "blue", "purple", "pink", "brown", "beige",
)  # fmt: skip


@dataclass
class Corrections:
    """What the user told us after a scan. It wins over the measurement and is never overwritten by a scan."""

    name: str | None = None  # e.g. "work bag"
    color: str | None = None
    height_m: float | None = None  # above the floor
    note: str | None = None
    confirmed: bool = False

    def is_empty(self) -> bool:
        return self == Corrections()


class ScanStatus(StrEnum):
    UPLOADING = "uploading"
    UPLOADED = "uploaded"
    PROCESSING = "processing"
    PROCESSED = "processed"
    FAILED = "failed"


@dataclass(frozen=True)
class ScanChange:
    """One difference a rescan found: a thing moved, new, or gone; places in words ("near the desk")."""

    kind: str  # "moved", "new", "gone"
    object_id: str
    label: str
    name: str | None = None
    color: str | None = None
    from_place: str | None = None
    to_place: str | None = None


@dataclass
class Scan:
    """Aggregate: one walkthrough episode, from upload to ingested results."""

    id: str
    home_id: str
    room: str
    status: ScanStatus
    archive_size: int
    archive_sha256: str
    part_size: int
    created_at: datetime
    detail: str | None = None
    frame_count: int | None = None
    object_count: int | None = None
    transform_to_home: tuple[float, ...] | None = None
    aligned_to: str | None = None  # a rescan recognised in this earlier scan's map (same frame)
    fresh: bool = False  # the room was scanned before but not recognised: its memory started over
    changes: list[ScanChange] = field(default_factory=list)

    @property
    def folder(self) -> str:
        """Where the scan's files live: readable and sortable by time, e.g.
        scans/2026-10-30T042101Z_living-room_7a736bf2-…; the id at the end keeps it unique."""
        slug = re.sub(r"[^a-z0-9]+", "-", self.room.lower()).strip("-")[:32] or "room"
        return f"scans/{self.created_at.astimezone(UTC):%Y-%m-%dT%H%M%SZ}_{slug}_{self.id}"

    @property
    def part_count(self) -> int:
        return max(1, math.ceil(self.archive_size / self.part_size))

    def expected_part_size(self, number: int) -> int:
        if not 1 <= number <= self.part_count:
            raise ValueError(f"part {number} is outside 1..{self.part_count}")
        if number < self.part_count:
            return self.part_size
        return self.archive_size - self.part_size * (self.part_count - 1)


@dataclass
class Home:
    """Aggregate: the floor plane, the room model and the landmarks."""

    id: str
    name: str
    room_model: RoomModel | None = None
    landmarks: list[Landmark] = field(default_factory=list)
    first_scan_id: str | None = None
