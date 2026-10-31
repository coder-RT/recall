from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from recall_api.domain.memory import Landmark, Position


class HeightBand(StrEnum):
    FLOOR = "floor"
    KNEE = "knee"
    WAIST = "waist"
    CHEST = "chest"
    HEAD = "head"


@dataclass(frozen=True)
class SpatialConfig:
    band_edges: tuple[float, float, float, float] = (0.3, 0.7, 1.1, 1.5)
    on_tolerance_m: float = 0.05
    near_radius_m: float = 1.5
    shelf_gap_m: float = 0.15


DEFAULT = SpatialConfig()


def height_band(z: float, cfg: SpatialConfig = DEFAULT) -> HeightBand:
    bands = (HeightBand.FLOOR, HeightBand.KNEE, HeightBand.WAIST, HeightBand.CHEST)
    for edge, band in zip(cfg.band_edges, bands, strict=True):
        if z < edge:
            return band
    return HeightBand.HEAD


@dataclass(frozen=True)
class Relation:
    """Where an object is relative to the nearest landmark; landmark None means room only."""

    landmark: Landmark | None
    kind: str | None  # "on", "left_of", "right_of", "near"
    distance_m: float | None
    band: HeightBand


def relate(obj: Position, landmarks: list[Landmark], cfg: SpatialConfig = DEFAULT) -> Relation:
    band = height_band(obj.z, cfg)
    # "on": base within tolerance of the top surface and inside the footprint; the highest such surface wins
    supports = [
        lm
        for lm in landmarks
        if lm.bbox.contains_xy(obj, margin=0.02)
        and abs(obj.z - lm.bbox.top_z) <= cfg.on_tolerance_m + 0.25
        and obj.z >= lm.bbox.top_z - cfg.on_tolerance_m
    ]
    if supports:
        lm = max(supports, key=lambda s: s.bbox.top_z)
        return Relation(lm, "on", 0.0, band)
    near = [(lm, obj.distance_to(lm.centroid)) for lm in landmarks]
    near = [(lm, d) for lm, d in near if d <= cfg.near_radius_m]
    if not near:
        return Relation(None, None, None, band)
    lm, d = min(near, key=lambda t: t[1])
    if lm.front_dir is not None:
        fx, fy = lm.front_dir
        dx, dy = obj.x - lm.centroid.x, obj.y - lm.centroid.y
        # as seen by someone standing at the front and facing the landmark (the way a walker arrives):
        # their forward is −front, so an offset with cross(front, offset) < 0 is on their left
        cross = fx * dy - fy * dx
        if abs(cross) > 0.15:
            return Relation(lm, "left_of" if cross < 0 else "right_of", d, band)
    return Relation(lm, "near", d, band)


def shelf_level(obj_z: float, shelf_tops: list[float], gap: float = SpatialConfig.shelf_gap_m) -> int | None:
    """1-based level counted from the bottom: the highest shelf top at or below the object (within `gap`)."""
    below = sorted(t for t in shelf_tops if t <= obj_z + gap)
    return len(below) if below else None
