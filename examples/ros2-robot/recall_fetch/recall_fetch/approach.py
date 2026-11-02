"""Where the robot should stop to "find" a thing: a free, reachable spot about half a metre from it, facing it.

Pure NumPy/SciPy on the exported map, so it is tested without ROS. Never a cell inside an obstacle or unknown space,
never one closer to anything than the robot's radius, and only cells connected to where the robot is.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from scipy import ndimage

from .export_map import FREE, Grid


@dataclass(frozen=True)
class Approach:
    x: float
    y: float
    yaw: float  # radians, facing the thing (0 = +x, counter-clockwise, as ROS)
    distance_m: float  # from the stop to the thing, on the floor

    @property
    def quaternion(self) -> tuple[float, float, float, float]:
        """x, y, z, w for a rotation about z."""
        return 0.0, 0.0, math.sin(self.yaw / 2), math.cos(self.yaw / 2)


def clearance_m(grid: Grid) -> np.ndarray:
    """Metres from each cell's centre to the nearest cell that is not free (obstacle or unknown)."""
    free = grid.cells == FREE
    return np.maximum(ndimage.distance_transform_edt(free) * grid.resolution - grid.resolution / 2, 0.0)


def choose(
    grid: Grid,
    thing: tuple[float, float],
    robot: tuple[float, float],
    robot_radius: float = 0.2,
    standoff: float = 0.5,
    give: float = 0.3,
    max_reach: float = 1.5,
) -> Approach | None:
    """The best stop near `thing` the robot at `robot` can drive to; None when no such spot exists."""
    safe = (grid.cells == FREE) & (clearance_m(grid) >= robot_radius)
    start = grid.cell(*robot)
    if start is None:
        return None
    labels, _ = ndimage.label(safe)
    if not safe[start]:  # the robot may sit just inside the margin: start from the nearest safe cell
        rows, cols = np.nonzero(safe)
        if len(rows) == 0:
            return None
        i = int(np.argmin((rows - start[0]) ** 2 + (cols - start[1]) ** 2))
        start = (int(rows[i]), int(cols[i]))
    reachable = labels == labels[start]
    rows, cols = np.nonzero(reachable)
    xs = grid.origin[0] + (cols + 0.5) * grid.resolution
    ys = grid.origin[1] + (rows + 0.5) * grid.resolution
    d = np.hypot(xs - thing[0], ys - thing[1])
    ring = np.abs(d - standoff) <= give
    if not ring.any():
        ring = d <= max_reach  # nothing at the ideal distance: the closest reachable spot within reach
        if not ring.any():
            return None
    score = np.where(ring, np.abs(d - standoff), np.inf)
    i = int(np.argmin(score))
    yaw = math.atan2(thing[1] - ys[i], thing[0] - xs[i])
    return Approach(float(xs[i]), float(ys[i]), yaw, float(d[i]))
