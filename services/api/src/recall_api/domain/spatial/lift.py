"""From a box in an arrival photo to a point in the home: the LiDAR depth inside the box, back-projected through the
camera and moved into the home frame. ARKit camera: +x right, +y up, looking along -z; image rows grow downwards."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class CameraView:
    pose: np.ndarray  # (4, 4) camera-to-world, ARKit world
    fx: float
    fy: float
    cx: float
    cy: float
    image_size: tuple[int, int]  # (w, h) of the photo the intrinsics and boxes are for
    depth: np.ndarray  # (h, w) metres, 0 = none


def lift_box(view: CameraView, box: tuple[float, float, float, float], inner: float = 0.6) -> np.ndarray | None:
    """World point (ARKit) of the box's middle, at the median depth of its inner part; None without depth there."""
    x1, y1, x2, y2 = box
    dh, dw = view.depth.shape
    sx, sy = dw / view.image_size[0], dh / view.image_size[1]
    mx, my = (x2 - x1) * (1 - inner) / 2, (y2 - y1) * (1 - inner) / 2
    c0, c1 = int(np.floor((x1 + mx) * sx)), int(np.ceil((x2 - mx) * sx))
    r0, r1 = int(np.floor((y1 + my) * sy)), int(np.ceil((y2 - my) * sy))
    patch = view.depth[max(r0, 0) : max(min(r1, dh), r0 + 1), max(c0, 0) : max(min(c1, dw), c0 + 1)]
    valid = patch[(patch > 0.1) & (patch < 6.0)]
    if valid.size == 0:
        return None
    d = float(np.median(valid))
    u, v = (x1 + x2) / 2, (y1 + y2) / 2
    camera = np.array([(u - view.cx) / view.fx * d, -(v - view.cy) / view.fy * d, -d, 1.0])
    return (view.pose @ camera)[:3]


def clock_and_distance(camera_pose_home: np.ndarray, point_home: np.ndarray) -> tuple[int, float]:
    """Clock-face direction (12 = straight ahead) and floor distance from the camera to a point, both in the home
    frame (z up). The camera looks along its -z axis."""
    at = camera_pose_home[:3, 3]
    fwd = -camera_pose_home[:3, 2]
    f = fwd[:2] / (np.linalg.norm(fwd[:2]) or 1.0)
    d = point_home[:2] - at[:2]
    dist = float(np.linalg.norm(d))
    if dist < 1e-6:
        return 12, 0.0
    ang = np.degrees(np.arctan2(f[0] * d[1] - f[1] * d[0], f @ d))  # + = to the left (counter-clockwise)
    hour = int(round((-ang % 360) / 30)) % 12
    return (12 if hour == 0 else hour), dist
