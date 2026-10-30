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


@dataclass
class FloorGrid:
    """Free/blocked cells on the floor (home frame, metres). `clearance` is metres to the nearest obstacle."""

    origin: np.ndarray  # (2,) world x, y of cell (0, 0)
    cell: float
    blocked: np.ndarray  # (H, W) bool: obstacles inflated by the body radius, plus unknown space
    clearance: np.ndarray  # (H, W) metres to the nearest raw obstacle or unknown cell

    @staticmethod
    def from_points(points: np.ndarray, cfg: NavConfig | None = None) -> FloorGrid:
        cfg = cfg or NavConfig()
        xy = points[:, :2]
        lo = xy.min(0) - cfg.cell_m
        size = np.ceil((xy.max(0) + cfg.cell_m - lo) / cfg.cell_m).astype(int)
        idx = np.floor((xy - lo) / cfg.cell_m).astype(int)
        floor = np.zeros(size[::-1], int)
        obst = np.zeros(size[::-1], bool)
        z = points[:, 2]
        on_floor = np.abs(z) < 0.06
        np.add.at(floor, (idx[on_floor, 1], idx[on_floor, 0]), 1)
        is_obst = (z >= cfg.obstacle_min_z) & (z <= cfg.obstacle_max_z)
        obst[idx[is_obst, 1], idx[is_obst, 0]] = True
        known_free = (floor >= cfg.min_floor_hits) & ~obst
        known_free = ndimage.binary_closing(known_free, iterations=1)  # fill single-cell holes in the floor scan
        raw_blocked = ~known_free | obst
        return FloorGrid.from_blocked(raw_blocked, lo, cfg)

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
