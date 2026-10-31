from __future__ import annotations

import heapq
import math

import numpy as np

from .grid import FloorGrid, NavConfig


class NoSafePath(Exception):
    """No route keeps a body's width of clearance; the Guide falls back to landmark directions."""


def _nearest_free(grid: FloorGrid, rc: tuple[int, int], max_r: int = 15) -> tuple[int, int] | None:
    if not grid.blocked[rc]:
        return rc
    free = np.argwhere(~grid.blocked)
    if len(free) == 0:
        return None
    d = np.abs(free - np.array(rc)).max(1)
    best = free[d.argmin()]
    return (int(best[0]), int(best[1])) if d.min() <= max_r else None


def plan(
    grid: FloorGrid, start: tuple[float, float], goal: tuple[float, float], cfg: NavConfig | None = None
) -> list[tuple[float, float]]:
    """A* over free cells; each step costs its length plus a penalty that grows near obstacles (keeps to the middle).

    The goal is the free cell nearest the object (the object itself sits on furniture, which is blocked).
    """
    cfg = cfg or NavConfig()
    s = _nearest_free(grid, grid.cell_of(*start), max_r=5)
    g = _nearest_free(grid, grid.cell_of(*goal), max_r=int(1.2 / grid.cell))
    if s is None or g is None:
        raise NoSafePath("the start or the object is not reachable with a body's width of space")
    h, w = grid.blocked.shape
    penalty = cfg.clearance_weight / np.maximum(grid.clearance, grid.cell)
    moves = [(dr, dc, math.hypot(dr, dc)) for dr in (-1, 0, 1) for dc in (-1, 0, 1) if dr or dc]
    best = {s: 0.0}
    came: dict[tuple[int, int], tuple[int, int]] = {}
    heap = [(0.0, s)]
    while heap:
        _, cur = heapq.heappop(heap)
        if cur == g:
            path = [cur]
            while cur in came:
                cur = came[cur]
                path.append(cur)
            return [grid.centre(c) for c in reversed(path)]
        for dr, dc, step in moves:
            n = (cur[0] + dr, cur[1] + dc)
            if not (0 <= n[0] < h and 0 <= n[1] < w) or grid.blocked[n]:
                continue
            if dr and dc and (grid.blocked[cur[0] + dr, cur[1]] or grid.blocked[cur[0], cur[1] + dc]):
                continue  # no corner cutting
            cost = best[cur] + step * grid.cell * (1 + penalty[n])
            if cost < best.get(n, math.inf):
                best[n] = cost
                came[n] = cur
                heapq.heappush(heap, (cost + math.dist(n, g) * grid.cell, n))
    raise NoSafePath("no path keeps a body's width of space")


def simplify(path: list[tuple[float, float]], tol: float = 0.15) -> list[tuple[float, float]]:
    """Douglas–Peucker: keep only the corners that matter (turns), within `tol` metres."""
    if len(path) < 3:
        return list(path)
    a, b = np.array(path[0]), np.array(path[-1])
    ab = b - a
    n = np.linalg.norm(ab) or 1.0
    d = [abs(ab[0] * (p[1] - a[1]) - ab[1] * (p[0] - a[0])) / n for p in path[1:-1]]
    i = int(np.argmax(d)) + 1
    if d[i - 1] <= tol:
        return [path[0], path[-1]]
    return simplify(path[: i + 1], tol)[:-1] + simplify(path[i:], tol)


def clock(heading_xy: tuple[float, float], to_xy: tuple[float, float]) -> int:
    """Turn as a clock face: 12 straight ahead, 3 right, 9 left (home frame is z up, so +angle is to the left)."""
    a = math.atan2(to_xy[1], to_xy[0]) - math.atan2(heading_xy[1], heading_xy[0])
    deg = (-math.degrees(a)) % 360  # clockwise from straight ahead
    hour = round(deg / 30) % 12
    return 12 if hour == 0 else hour


def to_clock_steps(waypoints: list[tuple[float, float]], heading_xy: tuple[float, float]) -> list[dict]:
    steps = []
    heading = heading_xy
    for a, b in zip(waypoints, waypoints[1:], strict=False):
        v = (b[0] - a[0], b[1] - a[1])
        metres = math.hypot(*v)
        if metres < 0.05:
            continue
        h = clock(heading, v)
        turn = "Straight ahead" if h == 12 else f"Turn to {h} o'clock"
        steps.append(
            {
                "clock": h,
                "metres": round(metres, 1),
                "say": f"{turn}, then about {_say_m(metres)}.",
                "waypoint": [round(b[0], 2), round(b[1], 2)],
            }
        )
        heading = v
    return steps


def _say_m(m: float) -> str:
    if m < 1:
        return f"{int(round(m * 10)) * 10} centimetres"
    return f"{m:.1f} metres".replace(".0 metres", " metres")
