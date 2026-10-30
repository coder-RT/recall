"""Rerun debug viewer (RERUN=1, dev only): every stage on one timeline. A no-op logger otherwise."""

from __future__ import annotations

import numpy as np

from recall_pipeline.application.ports import ViewGeometry


class NoDebug:
    def frame(self, view: ViewGeometry, rgb: np.ndarray) -> None: ...
    def points(self, name: str, pts: np.ndarray, colors: np.ndarray | None = None) -> None: ...
    def boxes3d(self, name: str, centers: np.ndarray, half_sizes: np.ndarray, labels: list[str]) -> None: ...


class RerunDebug:
    def __init__(self, recording: str = "recall") -> None:
        import rerun as rr  # dev dependency only

        self.rr = rr
        rr.init(recording, spawn=True)
        rr.log("world", rr.ViewCoordinates.RIGHT_HAND_Z_UP, static=True)

    def frame(self, view: ViewGeometry, rgb: np.ndarray) -> None:
        rr = self.rr
        rr.set_time("frame", sequence=view.index)
        h, w = view.depth.shape
        rr.log("arkit/camera", rr.Transform3D(translation=view.cam2world[:3, 3], mat3x3=view.cam2world[:3, :3]))
        rr.log("arkit/camera/image", rr.Pinhole(image_from_camera=view.intrinsics, width=w, height=h))
        rr.log("arkit/camera/image/depth", rr.DepthImage(view.depth, meter=1.0))
        rr.log("arkit/camera/rgb", rr.Image(rgb))

    def points(self, name: str, pts: np.ndarray, colors: np.ndarray | None = None) -> None:
        self.rr.log(f"world/{name}", self.rr.Points3D(pts, colors=colors, radii=0.005), static=True)

    def boxes3d(self, name: str, centers: np.ndarray, half_sizes: np.ndarray, labels: list[str]) -> None:
        self.rr.log(
            f"world/{name}", self.rr.Boxes3D(centers=centers, half_sizes=half_sizes, labels=labels), static=True
        )
