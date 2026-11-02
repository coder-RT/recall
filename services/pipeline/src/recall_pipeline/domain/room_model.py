"""room.json from fitted planes and detected furniture, in the home frame (metres). Shapely for the 2D geometry."""

from __future__ import annotations

import math
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


Segment = tuple[tuple[float, float], tuple[float, float], float]

WALL_MERGE_ANGLE_DEG = 10.0  # two planes this close in direction …
WALL_MERGE_GAP_M = 0.35  # … and this close together are one wall seen twice (its face and a cabinet front, a curtain)


def merge_walls(
    segs: list[Segment],
    centre: tuple[float, float],
    max_angle_deg: float = WALL_MERGE_ANGLE_DEG,
    max_gap: float = WALL_MERGE_GAP_M,
) -> list[Segment]:
    """One segment per real wall. RANSAC often finds a wall twice: its face and a parallel plane a few centimetres in
    front of it (furniture backs, a curtain, a radiator). Near-parallel segments whose lines are within `max_gap` of
    each other and whose spans overlap become one wall: it keeps the line of the outer segment (farther from `centre`,
    the room's middle, since the room is inside its walls), spans both, and takes the larger height."""
    c = np.asarray(centre, dtype=float)
    out = [(np.asarray(a, float), np.asarray(b, float), h) for a, b, h in segs]
    out.sort(key=lambda s: -float(np.linalg.norm(s[1] - s[0])))
    cos_max = math.cos(math.radians(max_angle_deg))

    def line(s):  # unit direction and the signed distance of the centre from the line
        u = (s[1] - s[0]) / (np.linalg.norm(s[1] - s[0]) or 1.0)
        n = np.array([-u[1], u[0]])
        return u, n, float((c - s[0]) @ n)

    merged = True
    while merged:
        merged = False
        for i in range(len(out)):
            for j in range(i + 1, len(out)):
                ui, ni, _ = line(out[i])
                uj, _, _ = line(out[j])
                if abs(float(ui @ uj)) < cos_max:
                    continue
                mid_j = (out[j][0] + out[j][1]) / 2
                if abs(float((mid_j - out[i][0]) @ ni)) > max_gap:
                    continue
                si = sorted(float((p - out[i][0]) @ ui) for p in out[i][:2])
                sj = sorted(float((p - out[i][0]) @ ui) for p in out[j][:2])
                if min(si[1], sj[1]) - max(si[0], sj[0]) < 0:
                    continue  # side by side along one line (two walls of a corridor), not the same wall twice
                outer, inner = sorted((out[i], out[j]), key=lambda s: -abs(line(s)[2]))
                u = line(outer)[0]
                ts = [float((p - outer[0]) @ u) for p in (*outer[:2], *inner[:2])]
                a, b = outer[0] + u * min(ts), outer[0] + u * max(ts)
                out[i] = (a, b, max(outer[2], inner[2]))
                del out[j]
                merged = True
                break
            if merged:
                break
    return [((float(a[0]), float(a[1])), (float(b[0]), float(b[1])), h) for a, b, h in out]


def room_json(floor: Polygon, walls: list[WallPlane], furniture: list[tuple[str, np.ndarray]]) -> dict:
    middle = floor.centroid
    segs = merge_walls([wall_segment(w) for w in walls], (middle.x, middle.y))
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
