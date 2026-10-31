"""A processed scan's geometry from its episode folder: the cleaned point cloud and the path the phone walked, both in
the home frame (metres, z up, floor at 0). Shared by guidance and the robot export."""

from __future__ import annotations

import io
import json

import numpy as np

from recall_api.application.ports import BlobStore
from recall_api.domain.memory import Scan


def cloud(blobs: BlobStore, scan: Scan) -> np.ndarray | None:
    key = f"{scan.folder}/episode/home_cloud.npy"
    if not blobs.exists(key):
        return None
    return np.load(io.BytesIO(blobs.get(key))).astype(np.float64)


def walked(blobs: BlobStore, scan: Scan) -> np.ndarray | None:
    """The phone's floor positions during the scan, from the episode's poses.jsonl (ARKit) and the scan's transform."""
    key = f"{scan.folder}/episode/poses.jsonl"
    if not blobs.exists(key) or not scan.transform_to_home:
        return None
    T = np.array(scan.transform_to_home, dtype=float).reshape(4, 4)
    xy = []
    for line in blobs.get(key).decode().splitlines():
        if not line.strip():
            continue
        M = np.array(json.loads(line)["pose"], dtype=float).reshape(4, 4).T  # column-major
        xy.append((T @ np.append(M[:3, 3], 1.0))[:2])
    return np.array(xy) if xy else None
