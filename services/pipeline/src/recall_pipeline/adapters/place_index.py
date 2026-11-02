"""Builds a scan's place index (place_index.npz in the episode folder): ORB features of every keyframe, lifted to 3D
with the frame's own LiDAR depth and ARKit pose. Classic OpenCV features, no model. The API's photo matcher reads it.

    python -m recall_pipeline.adapters.place_index EPISODE_DIR [EPISODE_DIR ...]
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np

from recall_pipeline.domain.geometry import column_major_to_matrix
from recall_pipeline.domain.place_index import lift_keypoints

FORMAT = "recall-place-index/1"
FEATURES = 1000
LONG_EDGE = 640  # ORB runs on a 640-pixel frame (the API matches the phone's photo at the same size)


def orb() -> cv2.ORB:
    return cv2.ORB_create(nfeatures=FEATURES, scaleFactor=1.2, nlevels=8, fastThreshold=12)


def features(gray: np.ndarray, detector: cv2.ORB | None = None) -> tuple[np.ndarray, np.ndarray]:
    """Keypoints (N, 2) in the given image's pixels and their ORB descriptors (N, 32), on a 640-pixel copy."""
    h, w = gray.shape
    s = LONG_EDGE / max(h, w)
    small = cv2.resize(gray, (round(w * s), round(h * s)), interpolation=cv2.INTER_AREA) if s < 1 else gray
    kps, desc = (detector or orb()).detectAndCompute(small, None)
    if desc is None or not kps:
        return np.zeros((0, 2)), np.zeros((0, 32), np.uint8)
    uv = np.array([k.pt for k in kps], dtype=np.float64) / min(s, 1.0)
    return uv, desc


def build(episode_dir: str | Path) -> Path | None:
    """Writes place_index.npz next to the episode's frames; None when the episode has no frames or depth."""
    ep = Path(episode_dir)
    manifest = json.loads((ep / "manifest.json").read_text())
    k = manifest["intrinsics"]
    K = np.array([[k["fx"], 0, k["cx"]], [0, k["fy"], k["cy"]], [0, 0, 1.0]])
    size = (manifest["image"]["width"], manifest["image"]["height"])
    poses = {}
    for line in (ep / "poses.jsonl").read_text().splitlines():
        p = json.loads(line)
        if p.get("tracking", "normal") == "normal":  # a pose ARKit wasn't sure of would place the points wrongly
            poses[p["index"]] = column_major_to_matrix(p["pose"])
    detector = orb()
    descs, points, frames, frame_ids, frame_poses = [], [], [], [], []
    for index in sorted(poses):
        img, dep = ep / "frames" / f"{index:06d}.jpg", ep / "depth" / f"{index:06d}.png"
        if not img.exists() or not dep.exists():
            continue
        gray = cv2.imread(str(img), cv2.IMREAD_GRAYSCALE)
        depth = cv2.imread(str(dep), cv2.IMREAD_UNCHANGED)
        if gray is None or depth is None:
            continue
        uv, desc = features(gray, detector)
        xyz, keep = lift_keypoints(uv, depth, K, size, poses[index])
        if len(keep) < 20:
            continue
        descs.append(desc[keep])
        points.append(xyz.astype(np.float32))
        frames.append(np.full(len(keep), len(frame_ids), dtype=np.int32))
        frame_ids.append(index)
        frame_poses.append(poses[index].T.reshape(-1))  # column-major, as the phone writes it
    if not frame_ids:
        return None
    out = ep / "place_index.npz"
    np.savez_compressed(
        out,
        format=np.array(FORMAT),
        desc=np.concatenate(descs),
        xyz=np.concatenate(points),
        frame=np.concatenate(frames),
        frame_ids=np.array(frame_ids, dtype=np.int32),
        poses=np.array(frame_poses, dtype=np.float32),
        image_size=np.array(size, dtype=np.int32),
    )
    return out


def main(argv: list[str]) -> int:
    for d in argv:
        t0 = time.perf_counter()
        out = build(d)
        if out is None:
            print(f"{d}: no frames with depth, no index", file=sys.stderr)
            continue
        with np.load(out) as z:
            n, f = len(z["desc"]), len(z["frame_ids"])
        print(f"{out}: {f} keyframes, {n} points, {time.perf_counter() - t0:.1f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
