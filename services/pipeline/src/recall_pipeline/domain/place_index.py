"""A scan's place index: the keyframes' feature points lifted to 3D with the phone's own LiDAR depth and ARKit pose.

The API matches one photo from the phone against it to say which room the phone is in and where it stands there
(classic features + PnP, no model), alongside ARKit's own relocalisation. Everything is in the scan's ARKit world
(metres, y up), the frame the phone's saved room map uses.
"""

from __future__ import annotations

import numpy as np

from recall_pipeline.domain.geometry import arkit_to_opencv

DEPTH_MIN_M, DEPTH_MAX_M = 0.2, 6.0  # LiDAR is reliable in this range


def depth_at(depth_mm: np.ndarray, uv_depth: np.ndarray, reach: int = 2) -> np.ndarray:
    """Depth in metres at (fractional) depth-map pixels: the nearest pixel, or else the median of the valid pixels
    within `reach` (an edge pixel often has no LiDAR return); NaN where there is none or it is out of range."""
    h, w = depth_mm.shape
    out = np.full(len(uv_depth), np.nan)
    cols = np.clip(np.floor(uv_depth[:, 0]).astype(int), 0, w - 1)
    rows = np.clip(np.floor(uv_depth[:, 1]).astype(int), 0, h - 1)
    for i, (r, c) in enumerate(zip(rows, cols, strict=True)):
        v = float(depth_mm[r, c])
        if v <= 0:
            patch = depth_mm[max(r - reach, 0) : r + reach + 1, max(c - reach, 0) : c + reach + 1]
            valid = patch[patch > 0]
            v = float(np.median(valid)) if valid.size else 0.0
        m = v / 1000.0
        if DEPTH_MIN_M <= m <= DEPTH_MAX_M:
            out[i] = m
    return out


def lift_keypoints(
    uv: np.ndarray, depth_mm: np.ndarray, K: np.ndarray, image_size: tuple[int, int], cam2world_arkit: np.ndarray
) -> tuple[np.ndarray, np.ndarray]:
    """Image pixels (N, 2) of a keyframe → (world points (M, 3), indices of the kept pixels). `K` is for `image_size`
    (width, height); the depth map may be smaller (LiDAR is 256 x 192) and is sampled at the same relative spot."""
    if len(uv) == 0:
        return np.zeros((0, 3)), np.zeros(0, dtype=int)
    w_img, h_img = image_size
    dh, dw = depth_mm.shape
    z = depth_at(depth_mm, uv * np.array([dw / w_img, dh / h_img]))
    keep = np.flatnonzero(np.isfinite(z))
    z = z[keep]
    x = (uv[keep, 0] - K[0, 2]) / K[0, 0] * z
    y = (uv[keep, 1] - K[1, 2]) / K[1, 1] * z
    cam = np.stack([x, y, z], axis=1)
    T = arkit_to_opencv(cam2world_arkit)
    return cam @ T[:3, :3].T + T[:3, 3], keep
