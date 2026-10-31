"""The phone's own geometry, no model: LiDAR depth back-projected with the ARKit intrinsics and poses.

The fallback for MapAnything (`RECONSTRUCTOR=arkit_depth`). The output is already metric and in the ARKit world frame;
ARKit's depth confidence is applied by the episode source (low-confidence depth is 0, so invalid).
"""

from __future__ import annotations

import numpy as np

from recall_pipeline.application.ports import EpisodeSource, ViewGeometry
from recall_pipeline.domain.episode import Episode
from recall_pipeline.domain.geometry import arkit_to_opencv, backproject, scale_intrinsics

LONG_EDGE = 512  # about MapAnything's output size, so later steps see the same density
MAX_DEPTH_M = 5.0  # LiDAR is unreliable beyond this


class ArkitDepth:
    def reconstruct(self, episode: Episode, source: EpisodeSource, indices: list[int]) -> list[ViewGeometry]:
        w, h = episode.image_size
        s = LONG_EDGE / max(w, h)
        size = (round(w * s), round(h * s))
        K = scale_intrinsics(episode.intrinsics.matrix(), size[0] / w, size[1] / h)
        views = []
        for i in indices:
            depth = source.depth_m(i, size).astype(np.float64)
            valid = (depth > 0.1) & (depth < MAX_DEPTH_M)
            cam2world = arkit_to_opencv(episode.frames[i].pose_arkit)
            views.append(
                ViewGeometry(
                    index=i,
                    points=backproject(depth, K, cam2world),
                    valid=valid,
                    confidence=valid.astype(np.float32),
                    cam2world=cam2world,
                    intrinsics=K,
                    depth=depth,
                )
            )
        return views
