from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy import ndimage


@dataclass(frozen=True)
class NavConfig:
    cell_m: float = 0.10
    obstacle_min_z: float = 0.10
    obstacle_max_z: float = 1.80
    body_radius_m: float = 0.30
    clearance_weight: float = 2.0
    min_floor_hits: int = 1
    min_obstacle_hits: int = 3  # points per cell before it counts as an obstacle (one stray point is noise)
    walked_radius_cells: int = 1  # cells either side of the scan's walked path that count as free


@dataclass
class FloorGrid:
    """Free/blocked cells on the floor (home frame, metres). `clearance` is metres to the nearest obstacle."""

    origin: np.ndarray  # (2,) world x, y of cell (0, 0)
    cell: float
    blocked: np.ndarray  # (H, W) bool: obstacles inflated by the body radius, plus unknown space
    clearance: np.ndarray  # (H, W) metres to the nearest raw obstacle or unknown cell

    @staticmethod
    def from_points(points: np.ndarray, cfg: NavConfig | None = None, walked: np.ndarray | None = None) -> FloorGrid:
        """`walked`: the (N, 2) floor positions of the phone during the scan. A person walked there, so those cells
        are free even where the camera never saw the floor; clearance is kept from seen obstacles only, and floor
        nobody saw or walked is never entered (but doesn't push the route away like a wall would)."""
        cfg = cfg or NavConfig()
        walked = np.zeros((0, 2)) if walked is None else np.asarray(walked, float).reshape(-1, 2)
        xy_all = np.vstack([points[:, :2], walked])
        lo = xy_all.min(0) - cfg.cell_m
        size = np.ceil((xy_all.max(0) + cfg.cell_m - lo) / cfg.cell_m).astype(int)
        idx = np.floor((points[:, :2] - lo) / cfg.cell_m).astype(int)
        floor = np.zeros(size[::-1], int)
        hits = np.zeros(size[::-1], int)
        z = points[:, 2]
        on_floor = np.abs(z) < 0.06
        np.add.at(floor, (idx[on_floor, 1], idx[on_floor, 0]), 1)
        is_obst = (z >= cfg.obstacle_min_z) & (z <= cfg.obstacle_max_z)
        np.add.at(hits, (idx[is_obst, 1], idx[is_obst, 0]), 1)
        obst = hits >= cfg.min_obstacle_hits
        seen_free = (floor >= cfg.min_floor_hits) & ~obst
        seen_free = ndimage.binary_closing(seen_free, iterations=1) & ~obst  # fill single-cell holes in the floor scan
        walked_cells = np.zeros(size[::-1], bool)
        if len(walked):
            w = np.floor((walked - lo) / cfg.cell_m).astype(int)
            walked_cells[w[:, 1], w[:, 0]] = True
            if cfg.walked_radius_cells > 0:
                walked_cells = ndimage.binary_dilation(walked_cells, iterations=cfg.walked_radius_cells)
        clearance = np.maximum(ndimage.distance_transform_edt(~obst) * cfg.cell_m - cfg.cell_m / 2, 0.0)
        blocked = ~(walked_cells | (seen_free & (clearance >= cfg.body_radius_m)))
        return FloorGrid(np.asarray(lo, float), cfg.cell_m, blocked, clearance)

    @staticmethod
    def from_blocked(raw_blocked: np.ndarray, origin, cfg: NavConfig | None = None) -> FloorGrid:
        cfg = cfg or NavConfig()
        # distance from a cell's centre to the nearest obstacle cell's EDGE (centre-to-centre overstates by half a cell)
        clearance = np.maximum(ndimage.distance_transform_edt(~raw_blocked) * cfg.cell_m - cfg.cell_m / 2, 0.0)
        blocked = clearance < cfg.body_radius_m  # a cell whose centre is closer than the body radius is unsafe
        return FloorGrid(np.asarray(origin, float), cfg.cell_m, blocked, clearance)

    def cell_of(self, x: float, y: float) -> tuple[int, int]:
        c = np.floor((np.array([x, y]) - self.origin) / self.cell).astype(int)
        return int(np.clip(c[1], 0, self.blocked.shape[0] - 1)), int(np.clip(c[0], 0, self.blocked.shape[1] - 1))

    def centre(self, rc: tuple[int, int]) -> tuple[float, float]:
        return (float(self.origin[0] + (rc[1] + 0.5) * self.cell), float(self.origin[1] + (rc[0] + 0.5) * self.cell))
