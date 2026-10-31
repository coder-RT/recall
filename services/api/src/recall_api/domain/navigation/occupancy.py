"""A robot's map of a room: free, occupied and unknown floor cells, in the form ROS's Nav2 map server reads.

Unlike FloorGrid (made for a person: obstacles grown by a body radius), this is the raw map: a robot's navigation
stack grows obstacles by its own size. Home frame: metres, z up, floor at z = 0; the map frame is the home frame.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy import ndimage

from .grid import NavConfig

FREE, OCCUPIED, UNKNOWN = 0, 100, -1  # ROS nav_msgs/OccupancyGrid values

# PGM shades for Nav2's "trinary" map mode with negate 0: occupancy = (255 - shade) / 255
PGM_FREE, PGM_OCCUPIED, PGM_UNKNOWN = 254, 0, 128
OCCUPIED_THRESH, FREE_THRESH = 0.65, 0.25  # 128 -> 0.498: between the two, so unknown


@dataclass(frozen=True)
class OccupancyMap:
    origin: tuple[float, float]  # world x, y of the lower-left corner of cell (0, 0)
    resolution: float  # metres per cell
    cells: np.ndarray  # (H, W) int8: FREE, OCCUPIED or UNKNOWN; row 0 is the lowest y

    @staticmethod
    def from_points(points: np.ndarray, walked: np.ndarray | None = None, cfg: NavConfig | None = None) -> OccupancyMap:
        """Occupied: enough points between knee-low and head height; free: floor the scan saw, or where the person
        walked; unknown: the rest."""
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
        occupied = hits >= cfg.min_obstacle_hits
        free = ndimage.binary_closing((floor >= cfg.min_floor_hits) & ~occupied, iterations=1) & ~occupied
        if len(walked):
            w = np.floor((walked - lo) / cfg.cell_m).astype(int)
            free[w[:, 1], w[:, 0]] = True
            free &= ~occupied
        cells = np.full(size[::-1], UNKNOWN, np.int8)
        cells[free] = FREE
        cells[occupied] = OCCUPIED
        return OccupancyMap((float(lo[0]), float(lo[1])), cfg.cell_m, cells)

    @property
    def size(self) -> tuple[int, int]:
        """(width, height) in cells."""
        return self.cells.shape[1], self.cells.shape[0]

    def pgm(self) -> bytes:
        """Binary PGM (P5). Images are stored top row first, so the rows are flipped: the map's lowest y is the image's
        bottom row, as Nav2's map server expects with `origin` at the lower-left pixel."""
        shades = np.full(self.cells.shape, PGM_UNKNOWN, np.uint8)
        shades[self.cells == FREE] = PGM_FREE
        shades[self.cells == OCCUPIED] = PGM_OCCUPIED
        w, h = self.size
        return f"P5\n{w} {h}\n255\n".encode() + np.flipud(shades).tobytes()

    def yaml_fields(self, image: str = "map.pgm") -> dict:
        """map.yaml for Nav2's map server (trinary mode, no negation, origin yaw 0)."""
        return {
            "image": image,
            "mode": "trinary",
            "resolution": self.resolution,
            "origin": [round(self.origin[0], 4), round(self.origin[1], 4), 0.0],
            "negate": 0,
            "occupied_thresh": OCCUPIED_THRESH,
            "free_thresh": FREE_THRESH,
        }

    def cell_at(self, x: float, y: float) -> tuple[int, int] | None:
        """(row, col) of the cell holding world point (x, y); None outside the map."""
        c = int(np.floor((x - self.origin[0]) / self.resolution))
        r = int(np.floor((y - self.origin[1]) / self.resolution))
        h, w = self.cells.shape
        return (r, c) if 0 <= r < h and 0 <= c < w else None


def shade_to_cell(shade: int) -> int:
    """What Nav2's map server makes of a PGM shade in trinary mode (negate 0): the rule our values are chosen for."""
    occ = (255 - shade) / 255.0
    if occ > OCCUPIED_THRESH:
        return OCCUPIED
    if occ < FREE_THRESH:
        return FREE
    return UNKNOWN
