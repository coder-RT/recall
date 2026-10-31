"""room.json from fitted planes and detected furniture, in the home frame (metres). Shapely for the 2D geometry."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from shapely import MultiPoint, concave_hull
from shapely.geometry import Polygon


@dataclass(frozen=True)
class WallPlane:
    """A near-vertical plane n·p + d = 0 (home frame) and the inlier points that support it."""

    normal: np.ndarray
    d: float
    points: np.ndarray


def floor_polygon(floor_points_xy: np.ndarray, ratio: float = 0.3) -> Polygon:
    """Outline of the floor: a concave hull of the floor inliers (tight around an L-shaped room), simplified."""
    hull = concave_hull(MultiPoint(floor_points_xy[:, :2]), ratio=ratio)
    if not isinstance(hull, Polygon) or hull.is_empty:
        hull = MultiPoint(floor_points_xy[:, :2]).convex_hull
    return hull.simplify(0.05)


def wall_segment(w: WallPlane) -> tuple[tuple[float, float], tuple[float, float], float]:
    """A wall as a 2D segment: its inliers projected on the wall's horizontal direction, 2nd to 98th percentile."""
    n2 = w.normal[:2] / (np.linalg.norm(w.normal[:2]) or 1.0)
    along = np.array([-n2[1], n2[0]])
    xy = w.points[:, :2]
    s = xy @ along
    lo, hi = np.percentile(s, [2, 98])
    base = n2 * -w.d  # closest point of the wall line to the origin
    a, b = base + along * lo, base + along * hi
    height = float(np.percentile(w.points[:, 2], 98))
    return (float(a[0]), float(a[1])), (float(b[0]), float(b[1])), height


def footprint(points: np.ndarray) -> tuple[list[tuple[float, float]], float]:
    """Furniture footprint: the minimum rotated rectangle around the points (xy), and the top height (98th pct)."""
    rect = MultiPoint(points[:, :2]).minimum_rotated_rectangle
    coords = list(rect.exterior.coords)[:-1] if isinstance(rect, Polygon) else [tuple(points[0, :2])] * 3
    return [(float(x), float(y)) for x, y in coords], float(np.percentile(points[:, 2], 98))


def room_json(floor: Polygon, walls: list[WallPlane], furniture: list[tuple[str, np.ndarray]]) -> dict:
    segs = [wall_segment(w) for w in walls]
    outline = [(float(x), float(y)) for x, y in floor.exterior.coords][:-1]
    if Polygon(outline).exterior.is_ccw is False:
        outline.reverse()
    items = []
    for label, pts in furniture:
        fp, top = footprint(pts)
        items.append({"label": label, "footprint": [list(p) for p in fp], "top_z": round(top, 3)})
    heights = [h for *_, h in segs]
    return {
        "floor_polygon": [[round(x, 3), round(y, 3)] for x, y in outline],
        "walls": [
            {
                "start": [round(a[0], 3), round(a[1], 3)],
                "end": [round(b[0], 3), round(b[1], 3)],
                "height_m": round(h, 3),
            }
            for a, b, h in segs
        ],
        "furniture": items,
        "height_m": round(max(heights) if heights else 2.4, 3),
    }
