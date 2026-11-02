"""A Recall robot export, read back: the Nav2 map (map.pgm + map.yaml) and objects.json. No ROS needed here.

Frames: the map frame is Recall's home frame (metres, z up, floor at z = 0). The PGM's top row is the map's highest y;
`origin` is the world position of the lower-left pixel. Cells: row 0 is the lowest y, as in ROS's OccupancyGrid.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import yaml

FREE, OCCUPIED, UNKNOWN = 0, 100, -1


@dataclass(frozen=True)
class Grid:
    cells: np.ndarray  # (H, W) int8, row 0 = lowest y
    resolution: float
    origin: tuple[float, float]

    def cell(self, x: float, y: float) -> tuple[int, int] | None:
        c = int(np.floor((x - self.origin[0]) / self.resolution))
        r = int(np.floor((y - self.origin[1]) / self.resolution))
        h, w = self.cells.shape
        return (r, c) if 0 <= r < h and 0 <= c < w else None

    def centre(self, r: int, c: int) -> tuple[float, float]:
        return self.origin[0] + (c + 0.5) * self.resolution, self.origin[1] + (r + 0.5) * self.resolution


def read_pgm(data: bytes) -> np.ndarray:
    """Binary P5 PGM -> (H, W) uint8 shades, image rows top first."""
    parts, rest = [], data
    while len(parts) < 4:  # magic, width, height, maxval (comments are not written by Recall)
        token, _, rest = rest.lstrip().partition(b"\n") if len(parts) == 0 else _next_token(rest)
        parts.append(token)
    w, h = int(parts[1]), int(parts[2])
    return np.frombuffer(rest[: w * h], np.uint8).reshape(h, w)


def _next_token(rest: bytes) -> tuple[bytes, bytes, bytes]:
    rest = rest.lstrip()
    for i, ch in enumerate(rest):
        if chr(ch).isspace():
            return rest[:i], b"", rest[i + 1 :]
    return rest, b"", b""


def load_grid(map_yaml: Path) -> Grid:
    """What Nav2's map server makes of the files (trinary mode, negate 0)."""
    meta = yaml.safe_load(map_yaml.read_text())
    shades = read_pgm((map_yaml.parent / meta["image"]).read_bytes()).astype(float)
    occ = (255 - shades) / 255.0 if not meta.get("negate") else shades / 255.0
    cells = np.full(shades.shape, UNKNOWN, np.int8)
    cells[occ > meta["occupied_thresh"]] = OCCUPIED
    cells[occ < meta["free_thresh"]] = FREE
    return Grid(np.flipud(cells), float(meta["resolution"]), (float(meta["origin"][0]), float(meta["origin"][1])))


def load_objects(objects_json: Path) -> dict:
    return json.loads(objects_json.read_text())
