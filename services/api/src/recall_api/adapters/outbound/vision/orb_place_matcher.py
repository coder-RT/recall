"""PlaceMatcher on classic OpenCV: one photo from the phone against a scan's place index (place_index.npz, written by
the pipeline: ORB features of every keyframe lifted to 3D with LiDAR depth and the ARKit pose).

1. ORB features of the photo (1000, on a 640-pixel copy: the same settings the index was built with).
2. Retrieval: every descriptor's nearest neighbour in the whole index votes for its keyframe; the 3 keyframes with the
   most close matches are kept.
3. Matching against those keyframes with Lowe's ratio test gives 2D–3D pairs; `solvePnPRansac` + LM refinement gives
   the camera's pose in the scan's ARKit world, and the RANSAC inliers are the score.
No model anywhere; the photo is decoded in memory and never stored.
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass
from functools import lru_cache

import cv2
import numpy as np

from recall_api.application.ports import BlobStore, PlaceMatch, PlaceQuery

FEATURES = 1000
LONG_EDGE = 640
CLOSE = 48  # Hamming distance that counts as a vote in retrieval (of 256 bits)
RATIO = 0.8
TOP_FRAMES = 3
REPROJ_PX = 4.0
_FLIP = np.diag([1.0, -1.0, -1.0, 1.0])  # OpenCV camera (+y down, +z forward) <-> ARKit camera (+y up, −z forward)


@dataclass(frozen=True)
class _Index:
    desc: np.ndarray  # (N, 32) uint8
    xyz: np.ndarray  # (N, 3) float32, the scan's ARKit world
    frame: np.ndarray  # (N,) keyframe row of each point
    starts: np.ndarray  # first point of each keyframe (points are stored keyframe by keyframe)
    frames: int


@lru_cache(maxsize=16)
def _load(path: str, mtime: float) -> _Index:  # mtime in the key: a rebuilt index is read again
    with np.load(path) as z:
        frame = z["frame"].astype(np.int64)
        n = int(len(z["frame_ids"]))
        return _Index(z["desc"], z["xyz"].astype(np.float64), frame, np.searchsorted(frame, np.arange(n + 1)), n)


class OrbPlaceMatcher:
    def __init__(self, blobs: BlobStore) -> None:
        self.blobs = blobs
        self.orb = cv2.ORB_create(nfeatures=FEATURES, scaleFactor=1.2, nlevels=8, fastThreshold=12)
        self.bf = cv2.BFMatcher(cv2.NORM_HAMMING)

    def _index(self, key: str) -> _Index | None:
        path = self.blobs.local_path(key)
        if not path or not os.path.exists(path):
            return None
        return _load(path, os.path.getmtime(path))

    def _features(self, jpeg: bytes) -> tuple[np.ndarray, np.ndarray]:
        gray = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_GRAYSCALE)
        if gray is None:
            return np.zeros((0, 2)), np.zeros((0, 32), np.uint8)
        h, w = gray.shape
        s = min(LONG_EDGE / max(h, w), 1.0)
        small = cv2.resize(gray, (round(w * s), round(h * s)), interpolation=cv2.INTER_AREA) if s < 1 else gray
        kps, desc = self.orb.detectAndCompute(small, None)
        if desc is None or not kps:
            return np.zeros((0, 2)), np.zeros((0, 32), np.uint8)
        return np.array([k.pt for k in kps], dtype=np.float64) / s, desc

    def match(self, query: PlaceQuery, candidates: dict[str, str], budget_s: float = 0.4) -> list[PlaceMatch]:
        """One result per candidate scan (scan id -> index key) that has an index, best first; scans not reached
        within the time budget are left out."""
        t0 = time.perf_counter()
        uv, desc = self._features(query.jpeg)
        if len(desc) < 30:
            return []
        K = np.array([[query.fx, 0, query.cx], [0, query.fy, query.cy], [0, 0, 1.0]])
        out = []
        for scan_id, key in candidates.items():
            if time.perf_counter() - t0 > budget_s:
                break
            idx = self._index(key)
            if idx is None:
                continue
            out.append(self._one(scan_id, idx, uv, desc, K))
        return sorted(out, key=lambda m: -m.inliers)

    def _one(self, scan_id: str, idx: _Index, uv: np.ndarray, desc: np.ndarray, K: np.ndarray) -> PlaceMatch:
        nearest = self.bf.match(desc, idx.desc)
        votes = np.bincount([idx.frame[m.trainIdx] for m in nearest if m.distance <= CLOSE], minlength=idx.frames)
        top = [int(f) for f in np.argsort(-votes)[:TOP_FRAMES] if votes[f] > 0]
        pairs: dict[int, tuple[float, int]] = {}  # query keypoint -> (distance, index point)
        for f in top:
            a, b = int(idx.starts[f]), int(idx.starts[f + 1])
            if b - a < 2:
                continue
            for m in self.bf.knnMatch(desc, idx.desc[a:b], k=2):
                if len(m) == 2 and m[0].distance < RATIO * m[1].distance:
                    q, d = m[0].queryIdx, m[0].distance
                    if q not in pairs or d < pairs[q][0]:
                        pairs[q] = (d, a + m[0].trainIdx)
        keyframe = top[0] if top else None
        if len(pairs) < 12:
            return PlaceMatch(scan_id, len(pairs) // 4, None, None, keyframe)
        q_idx = np.array(list(pairs))
        obj = idx.xyz[[pairs[q][1] for q in q_idx]]
        img = uv[q_idx]
        ok, rvec, tvec, inl = cv2.solvePnPRansac(
            obj, img, K, None, iterationsCount=300, reprojectionError=REPROJ_PX, confidence=0.995,
            flags=cv2.SOLVEPNP_EPNP,
        )  # fmt: skip
        if not ok or inl is None or len(inl) < 6:
            return PlaceMatch(scan_id, 0, None, None, keyframe)
        inl = inl[:, 0]
        rvec, tvec = cv2.solvePnPRefineLM(obj[inl], img[inl], K, None, rvec, tvec)
        proj, _ = cv2.projectPoints(obj[inl], rvec, tvec, K, None)
        err = float(np.mean(np.linalg.norm(proj[:, 0] - img[inl], axis=1)))
        R, _ = cv2.Rodrigues(rvec)
        world_to_cam = np.eye(4)
        world_to_cam[:3, :3], world_to_cam[:3, 3] = R, tvec[:, 0]
        cam2world = np.linalg.inv(world_to_cam) @ _FLIP  # OpenCV camera -> ARKit camera, same world
        return PlaceMatch(scan_id, int(len(inl)), tuple(float(v) for v in cam2world.T.reshape(-1)), err, keyframe)
