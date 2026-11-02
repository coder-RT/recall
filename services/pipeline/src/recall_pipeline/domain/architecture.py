"""Regenerate a scanned room as an architect would draw it, from measurements only (nothing is generated).

1. Manhattan frame: most rooms are built at right angles, so the walls' dominant direction (length-weighted, mod 90°)
   becomes the plan's x axis. Everything below is in that "plan frame"; `theta` turns it back into the home frame.
2. Plan: the measured floor outline is rasterised (5 cm), smoothed (closing then opening), and its boundary is made
   rectilinear: short edges (< 50 cm) are removed by merging the two parallel edges beside them at their length-weighted
   position, until only real corners remain.
3. Walls: each plan edge is "scanned" when a measured wall runs along it, otherwise "unscanned" (drawn dashed: the scan
   never saw that side, so the plan only says the floor ends there).
4. Doors become openings in their nearest wall; furniture becomes parametric parts (a desk is a top on four legs, a
   shelf two sides and boards, …) at the size of its points in the plan frame, coloured by the photos' median colour.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
from scipy import ndimage
from shapely import contains_xy
from shapely.geometry import Polygon, box
from shapely.ops import unary_union

WALL_T = 0.12  # drawn wall thickness, metres (outside the measured room)
DOOR_H = 2.05


def rotate(xy: np.ndarray, theta: float) -> np.ndarray:
    """Rotate points (…, 2) by theta (radians, counter-clockwise)."""
    c, s = math.cos(theta), math.sin(theta)
    return xy @ np.array([[c, s], [-s, c]])


def manhattan_angle(walls: list[tuple[tuple[float, float], tuple[float, float]]]) -> float:
    """The walls' dominant direction mod 90°, in [0, π/2): a length-weighted, circularly smoothed 1° histogram."""
    hist = np.zeros(90)
    for (x1, y1), (x2, y2) in walls:
        length = math.hypot(x2 - x1, y2 - y1)
        if length < 0.2:
            continue
        deg = math.degrees(math.atan2(y2 - y1, x2 - x1)) % 90
        hist[int(deg) % 90] += length
    if not hist.any():
        return 0.0
    smooth = sum(np.roll(hist, k) * w for k, w in ((-2, 1), (-1, 2), (0, 3), (1, 2), (2, 1)))
    peak = int(np.argmax(smooth))
    # refine within the peak's bins by the length-weighted mean
    near = [(peak + k) % 90 for k in range(-2, 3)]
    weights = hist[near]
    angles = np.array([peak + k for k in range(-2, 3)], dtype=float) + 0.5
    deg = float(np.average(angles, weights=weights)) if weights.sum() > 0 else peak + 0.5
    return math.radians(deg % 90)


def rectilinear(poly: Polygon, min_edge: float = 0.5) -> Polygon:
    """An axis-aligned polygon with every edge ≥ min_edge, from an axis-aligned staircase polygon."""
    ring = np.array(poly.exterior.coords)[:-1]
    # lines: (horizontal?, coordinate), one per maximal run of collinear edges
    lines: list[list[float]] = []
    for a, b in zip(ring, np.roll(ring, -1, axis=0), strict=True):
        horizontal = abs(b[1] - a[1]) < 1e-9
        coord = a[1] if horizontal else a[0]
        if lines and bool(lines[-1][0]) == horizontal:
            continue  # same run (collinear)
        lines.append([float(horizontal), float(coord)])
    if len(lines) > 1 and lines[0][0] == lines[-1][0]:
        lines.pop()
    while len(lines) > 4:
        n = len(lines)
        verts = _corners(lines)
        lengths = np.array([np.abs(verts[i] - verts[i - 1]).sum() for i in range(n)])  # edge i: vertex i-1 → i
        k = int(np.argmin(lengths))
        if lengths[k] >= min_edge:
            break
        prev, nxt = (k - 1) % n, (k + 1) % n
        lp, ln = lengths[prev], lengths[nxt]
        lines[prev][1] = (lines[prev][1] * lp + lines[nxt][1] * ln) / max(lp + ln, 1e-9)
        for i in sorted({k, nxt}, reverse=True):
            lines.pop(i)
    out = Polygon(_corners(lines))
    return out if out.is_valid and out.area > 0 else poly


def _corners(lines: list[list[float]]) -> np.ndarray:
    """Vertex i is where line i meets line i + 1 (they alternate horizontal and vertical)."""
    pts = []
    for i, (h, c) in enumerate(lines):
        _, c2 = lines[(i + 1) % len(lines)]
        pts.append((c2, c) if h else (c, c2))
    return np.array(pts)


def plan_outline(
    points_xy: np.ndarray, theta: float, floor_home: list[list[float]] | None = None, cell: float = 0.1
) -> Polygon:
    """The room's footprint as a clean rectilinear plan (in the plan frame).

    The footprint is where the scan has points (walls and furniture included, since the floor is often hidden),
    plus the measured floor outline: rasterised at `cell`, gaps up to ~80 cm closed, enclosed holes filled, thin
    spurs opened away; the largest piece is then made rectilinear.
    """
    xy = rotate(np.asarray(points_xy, dtype=float), -theta)
    lo = xy.min(0) - 2 * cell
    size = np.ceil((xy.max(0) + 2 * cell - lo) / cell).astype(int) + 1
    counts = np.zeros((size[1], size[0]), dtype=np.int32)
    ij = ((xy - lo) / cell).astype(int)
    np.add.at(counts, (ij[:, 1], ij[:, 0]), 1)
    grid = counts >= 3  # a lone stray point is not the room
    if floor_home:
        poly = Polygon(rotate(np.array(floor_home, dtype=float), -theta))
        xs = lo[0] + (np.arange(size[0]) + 0.5) * cell
        ys = lo[1] + (np.arange(size[1]) + 0.5) * cell
        gx, gy = np.meshgrid(xs, ys)
        grid |= contains_xy(poly, gx, gy)
    grid = ndimage.binary_closing(grid, iterations=4)
    grid = ndimage.binary_fill_holes(grid)
    grid = ndimage.binary_opening(grid, iterations=2)
    labels, n = ndimage.label(grid)
    if n == 0:
        return Polygon(xy).convex_hull
    biggest = 1 + int(np.argmax(ndimage.sum(grid, labels, range(1, n + 1))))
    rows, cols = np.nonzero(labels == biggest)
    cells = unary_union(
        [
            box(lo[0] + c * cell, lo[1] + r * cell, lo[0] + (c + 1) * cell, lo[1] + (r + 1) * cell)
            for r, c in zip(rows, cols, strict=True)
        ]
    )
    if cells.geom_type != "Polygon":
        cells = max(cells.geoms, key=lambda g: g.area)
    return rectilinear(Polygon(cells.exterior).simplify(1e-6))


@dataclass
class Wall:
    a: tuple[float, float]
    b: tuple[float, float]
    scanned: bool
    openings: list[dict] = field(default_factory=list)  # {kind, offset, width, height} along a → b

    @property
    def length(self) -> float:
        return math.hypot(self.b[0] - self.a[0], self.b[1] - self.a[1])


def walls_of(plan: Polygon, measured_plan: list[tuple[np.ndarray, np.ndarray]], tol: float = 0.35) -> list[Wall]:
    """The plan's edges as walls, marked scanned where a measured wall runs along them."""
    ring = list(plan.exterior.coords)[:-1]
    if not plan.exterior.is_ccw:
        ring = ring[::-1]  # counter-clockwise: the room is on each wall's left
    walls = []
    for a, b in zip(ring, ring[1:] + ring[:1], strict=True):
        a, b = np.array(a), np.array(b)
        d = b - a
        length = float(np.linalg.norm(d))
        u = d / max(length, 1e-9)
        covered = 0.0
        for p, q in measured_plan:
            seg = q - p
            seg_len = float(np.linalg.norm(seg))
            if seg_len < 0.2 or abs(float(np.dot(seg / seg_len, u))) < math.cos(math.radians(15)):
                continue

            if max(_off_line(a, u, p), _off_line(a, u, q)) > tol:
                continue
            s = sorted([float(np.dot(p - a, u)), float(np.dot(q - a, u))])
            covered += max(0.0, min(s[1], length) - max(s[0], 0.0))
        walls.append(Wall((float(a[0]), float(a[1])), (float(b[0]), float(b[1])), covered >= 0.35 * length))
    return walls


def _off_line(a: np.ndarray, u: np.ndarray, x: np.ndarray) -> float:
    """Distance from x to the line through a along unit u."""
    r = x - a
    return abs(float(u[0] * r[1] - u[1] * r[0]))


def place_door(walls: list[Wall], box_min: np.ndarray, box_max: np.ndarray) -> None:
    """A door box becomes an opening in the nearest wall."""
    centre = (box_min[:2] + box_max[:2]) / 2
    best, dist = None, math.inf
    for w in walls:
        a, b = np.array(w.a), np.array(w.b)
        u = (b - a) / max(w.length, 1e-9)
        t = float(np.clip(np.dot(centre - a, u), 0, w.length))
        d = float(np.linalg.norm(a + t * u - centre))
        if d < dist:
            best, dist = (w, t, u), d
    if best is None:
        return
    w, t, u = best
    extent = box_max[:2] - box_min[:2]
    width = float(np.clip(abs(extent @ u), 0.6, min(1.6, w.length - 0.1)))
    offset = float(np.clip(t - width / 2, 0.05, max(w.length - width - 0.05, 0.05)))
    w.openings.append({"kind": "door", "offset": round(offset, 3), "width": round(width, 3), "height": DOOR_H})


@dataclass(frozen=True)
class Part:
    kind: str  # what it is: top, leg, board, side, panel, seat, back, arm, base, mattress, headboard, box
    centre: tuple[float, float, float]  # plan frame
    size: tuple[float, float, float]


def fit_box(points_plan: np.ndarray, z_min: float, z_max: float) -> tuple[np.ndarray, np.ndarray] | None:
    """A furniture box in the plan frame from its points (2nd–98th percentile, so stray points don't stretch it)."""
    pts = points_plan[(points_plan[:, 2] >= z_min + 0.02) & (points_plan[:, 2] <= z_max)]
    if len(pts) < 20:
        return None
    lo, hi = np.percentile(pts, 2, axis=0), np.percentile(pts, 98, axis=0)
    lo[2], hi[2] = max(z_min, 0.0), z_max
    if np.any(hi[:2] - lo[:2] < 0.05):
        return None
    return lo, hi


def front_axis(lo: np.ndarray, hi: np.ndarray, toward: np.ndarray) -> tuple[int, int]:
    """(axis, sign) of the box side that faces `toward` (the room's centre): where a desk is used from, a TV seen."""
    d = toward - (lo[:2] + hi[:2]) / 2
    axis = 0 if abs(d[0]) >= abs(d[1]) else 1
    return axis, (1 if d[axis] >= 0 else -1)


def _part(kind: str, lo, hi) -> Part:
    lo, hi = np.asarray(lo, float), np.asarray(hi, float)
    return Part(kind, tuple(np.round((lo + hi) / 2, 3)), tuple(np.round(np.maximum(hi - lo, 0.01), 3)))


# furniture that always stands on the floor; SAM 3.1's masks seldom reach the legs, and a desk is often measured
# from its top only, so its box can start well above the floor
FLOOR_STANDING = {"desk", "table", "chair", "bed", "sofa", "cabinet"}
# a shelf may hang on a wall: grounded only when its box already starts low
GROUND_BELOW = 0.5


def furniture_parts(label: str, lo: np.ndarray, hi: np.ndarray, toward: np.ndarray) -> list[Part]:
    """Parametric parts for one piece of furniture, by kind, filling its measured box (standing on the floor)."""
    lo = np.array(lo, float)
    if label in FLOOR_STANDING or (label == "shelf" and lo[2] < GROUND_BELOW):
        lo[2] = 0.0
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    axis, sign = front_axis(lo, hi, toward)

    def back_slab(t: float, top: float) -> Part:  # a slab of thickness t along the back side, up to `top`
        a, b = np.array(lo, float), np.array([x1, y1, top])
        if sign > 0:
            b[axis] = lo[axis] + t
        else:
            a[axis] = hi[axis] - t
        return _part("back", a, b)

    def legs(top: float, w: float = 0.05, inset: float = 0.03) -> list[Part]:
        top = max(top, z0 + 0.05)  # a very short box still gets legs that go up from the floor, never down
        out = []
        for x in (x0 + inset, x1 - inset - w):
            for y in (y0 + inset, y1 - inset - w):
                out.append(_part("leg", (x, y, z0), (x + w, y + w, top)))
        return out

    kind = {"table": "desk"}.get(label, label)
    if kind == "desk":
        return [_part("top", (x0, y0, z1 - 0.03), (x1, y1, z1)), *legs(z1 - 0.03)]
    if kind == "shelf":
        long_axis = 0 if (x1 - x0) >= (y1 - y0) else 1
        parts = []
        for end in (lo[long_axis], hi[long_axis] - 0.02):
            a, b = np.array(lo, float), np.array(hi, float)
            a[long_axis], b[long_axis] = end, end + 0.02
            parts.append(_part("side", a, b))
        boards = max(2, round((z1 - z0) / 0.35) + 1)
        for z in np.linspace(z0, z1 - 0.02, boards):
            parts.append(_part("board", (x0, y0, z), (x1, y1, z + 0.02)))
        return parts
    if kind == "cabinet":
        return [_part("box", lo, hi)]
    if kind == "bed":
        return [
            _part("base", (x0, y0, z0), (x1, y1, min(z0 + 0.3, z1))),
            _part("mattress", (x0 + 0.03, y0 + 0.03, min(z0 + 0.3, z1)), (x1 - 0.03, y1 - 0.03, min(z0 + 0.5, z1))),
            _part("headboard", *_slab_bounds(back_slab(0.06, max(z1, z0 + 0.9)))),
        ]
    if kind == "sofa":
        seat = min(z0 + 0.42, z1)
        parts = [_part("base", (x0, y0, z0), (x1, y1, seat)), back_slab(0.2, z1)]
        side = 1 - axis  # arms at the two ends across the front axis
        for end in (lo[side], hi[side] - 0.15):
            a, b = np.array(lo, float), np.array([x1, y1, min(z0 + 0.62, z1)])
            a[side], b[side] = end, end + 0.15
            parts.append(_part("arm", a, b))
        return parts
    if kind == "chair":
        seat = max(min(z0 + 0.45, z1 - 0.05), z0 + 0.09)  # never below the floor, even for a very low box
        return [_part("seat", (x0, y0, seat - 0.04), (x1, y1, seat)), back_slab(0.05, z1), *legs(seat - 0.04, w=0.04)]
    if kind == "tv":
        return [back_slab(0.05, z1)]
    return [_part("box", lo, hi)]


def _slab_bounds(p: Part) -> tuple[np.ndarray, np.ndarray]:
    c, s = np.array(p.centre), np.array(p.size)
    return c - s / 2, c + s / 2


def hex_colour(rgb: np.ndarray | None, fallback: str) -> str:
    """The median colour of some points, or the fallback when there are too few."""
    if rgb is None or len(rgb) < 20:
        return fallback
    r, g, b = np.median(rgb, axis=0).astype(int)
    return f"#{r:02x}{g:02x}{b:02x}"
