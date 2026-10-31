"""Lift a 2D detection into 3D with the frame's depth, intrinsics and camera-to-world pose (OpenCV convention)."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class Lifted:
    centroid: np.ndarray  # (3,) world
    points: np.ndarray  # (N, 3) world, the depth samples inside the box
    depth_m: float


def backproject(depth_m: np.ndarray, K: np.ndarray, cam2world: np.ndarray, pixels: np.ndarray) -> np.ndarray:
    """pixels (N, 2) as (u, v) → world points (N, 3) using depth at those pixels. depth_m is (H, W) in metres."""
    u, v = pixels[:, 0], pixels[:, 1]
    z = depth_m[v, u]
    x = (u - K[0, 2]) * z / K[0, 0]
    y = (v - K[1, 2]) * z / K[1, 1]
    cam = np.stack([x, y, z, np.ones_like(z)], axis=1)
    return (cam2world @ cam.T).T[:, :3]


def lift_box(
    box: tuple[float, float, float, float],
    depth_m: np.ndarray,
    K: np.ndarray,
    cam2world: np.ndarray,
    inner: float = 0.6,
    min_samples: int = 12,
) -> Lifted | None:
    """The box's central `inner` fraction, sampled where depth is valid; the median depth band rejects background.

    Returns None when too few pixels have depth (e.g. the object is out of LiDAR range or on a glass surface).
    """
    h, w = depth_m.shape
    x1, y1, x2, y2 = box
    cx, cy, bw, bh = (x1 + x2) / 2, (y1 + y2) / 2, (x2 - x1) * inner, (y2 - y1) * inner
    us = np.clip(np.arange(int(cx - bw / 2), int(cx + bw / 2) + 1), 0, w - 1)
    vs = np.clip(np.arange(int(cy - bh / 2), int(cy + bh / 2) + 1), 0, h - 1)
    uu, vv = np.meshgrid(us, vs)
    pix = np.stack([uu.ravel(), vv.ravel()], axis=1)
    z = depth_m[pix[:, 1], pix[:, 0]]
    pix = pix[(z > 0.1) & np.isfinite(z)]
    if len(pix) < min_samples:
        return None
    z = depth_m[pix[:, 1], pix[:, 0]]
    med = float(np.median(z))
    keep = np.abs(z - med) < max(0.08, 0.1 * med)  # the object, not what is behind it
    pix = pix[keep]
    if len(pix) < min_samples:
        return None
    pts = backproject(depth_m, K, cam2world, pix)
    return Lifted(centroid=np.median(pts, axis=0), points=pts, depth_m=med)
