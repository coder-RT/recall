"""ARKit world (y up) → the home frame (z up, floor at z = 0), as one rigid 4x4 transform."""

from __future__ import annotations

import numpy as np

# ARKit world: +X right, +Y up, +Z toward the user at session start (right-handed). Home: z up, right-handed.
Y_UP_TO_Z_UP = np.array([[1, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]], dtype=np.float64)


def to_home(floor_height_arkit_y: float) -> np.ndarray:
    """The transform from ARKit world to home: rotate y-up to z-up, then lower so the floor is at z = 0."""
    T = Y_UP_TO_Z_UP.copy()
    T[2, 3] = -floor_height_arkit_y
    return T


def apply(T: np.ndarray, pts: np.ndarray) -> np.ndarray:
    return (T[:3, :3] @ pts.T).T + T[:3, 3]
