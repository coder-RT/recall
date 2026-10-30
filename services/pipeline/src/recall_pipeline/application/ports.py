"""What the pipeline needs from the outside world. Adapters implement these; adapters/run.py wires them."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol

import numpy as np

from recall_pipeline.domain.episode import Episode


class EpisodeSource(Protocol):
    """Reads an episode folder (the Mac's disk today; R2 later)."""

    def load(self) -> Episode: ...
    def image_rgb(self, index: int) -> np.ndarray: ...
    def jpeg(self, index: int) -> bytes: ...
    def depth_m(self, index: int, size: tuple[int, int]) -> np.ndarray:
        """Depth in metres resized to (width, height) of the image; 0 where unknown or low confidence."""
        ...


@dataclass(frozen=True)
class ViewGeometry:
    index: int
    points: np.ndarray  # (H, W, 3) world (ARKit frame), metres
    valid: np.ndarray  # (H, W) bool
    confidence: np.ndarray  # (H, W)
    cam2world: np.ndarray  # (4, 4) OpenCV convention, as MapAnything returns it
    intrinsics: np.ndarray  # (3, 3) at the output resolution
    depth: np.ndarray  # (H, W) metres at the output resolution


class Reconstructor(Protocol):
    """MapAnything: per-frame metric geometry in the ARKit world frame."""

    def reconstruct(self, episode: Episode, source: EpisodeSource, indices: list[int]) -> list[ViewGeometry]: ...


@dataclass(frozen=True)
class Box:
    label: str
    score: float
    box: tuple[float, float, float, float]  # x1, y1, x2, y2 in source pixels, inclusive


class Segmenter(Protocol):
    """SAM 3.1: every instance of one concept in one frame (one concept per request)."""

    def boxes(self, jpeg: bytes, concept: str) -> list[Box]: ...


@dataclass(frozen=True)
class Plane:
    normal: np.ndarray  # unit, pointing up for the floor
    d: float  # n·p + d = 0
    inliers: np.ndarray  # (N, 3)


class PointCloudOps(Protocol):
    """Classic geometry (Open3D): clean-up, planes, clustering, registration. No ML modules."""

    def clean(self, points: np.ndarray) -> np.ndarray: ...
    def floor_and_walls(self, points: np.ndarray) -> tuple[Plane, list[Plane]]: ...
    def clusters(self, points: np.ndarray, eps: float, min_points: int) -> np.ndarray:
        """Cluster label per point (−1 = noise)."""
        ...


class ResultSink(Protocol):
    """Posts the results to the API (the only writer of memory)."""

    def post(self, scan_id: str, result: dict[str, Any]) -> None: ...


class DebugLog(Protocol):
    """Rerun when RERUN=1; a no-op otherwise. Never needed for tests or make demo."""

    def frame(self, view: ViewGeometry, rgb: np.ndarray) -> None: ...
    def points(self, name: str, pts: np.ndarray, colors: np.ndarray | None = None) -> None: ...
    def boxes3d(self, name: str, centers: np.ndarray, half_sizes: np.ndarray, labels: list[str]) -> None: ...
