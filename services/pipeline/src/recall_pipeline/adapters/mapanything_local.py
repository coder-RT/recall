"""MapAnything on the Mac's GPU (MPS) with the phone's metric inputs: intrinsics, poses and LiDAR depth."""

from __future__ import annotations

import logging

import numpy as np
import torch

from recall_pipeline.application.ports import EpisodeSource, ViewGeometry
from recall_pipeline.domain.episode import Episode
from recall_pipeline.domain.geometry import arkit_to_opencv

log = logging.getLogger("recall_pipeline")

WEIGHTS = "facebook/map-anything-apache"
REVISION = "00f9c245bbcb60522d1ed7f9e9d88462c6e3f38a"


class MapAnythingLocal:
    name = f"map-anything-apache@{REVISION[:7]}"

    def __init__(self) -> None:
        from mapanything.models import MapAnything
        from mapanything.utils.device import get_device

        self.device = get_device()
        self.model = MapAnything.from_pretrained(WEIGHTS, revision=REVISION).to(self.device)
        self.model.eval()

    def reconstruct(self, episode: Episode, source: EpisodeSource, indices: list[int]) -> list[ViewGeometry]:
        from mapanything.utils.image import preprocess_inputs

        w, h = episode.image_size
        K = torch.tensor(episode.intrinsics.matrix(), dtype=torch.float32)
        views = []
        for i in indices:
            f = episode.frames[i]
            views.append(
                {
                    "img": torch.from_numpy(source.image_rgb(i)),
                    "intrinsics": K,
                    "depth_z": torch.from_numpy(source.depth_m(i, (w, h))),
                    "camera_poses": torch.tensor(arkit_to_opencv(f.pose_arkit), dtype=torch.float32),
                    "is_metric_scale": torch.tensor([True]),
                }
            )
        with torch.no_grad():
            out = self.model.infer(
                preprocess_inputs(views),
                memory_efficient_inference=True,
                minibatch_size=1,
                use_amp=True,
                amp_dtype="bf16",
                apply_mask=True,
                mask_edges=True,
            )
        # MapAnything expresses everything in view 0's camera frame (model.py,
        # _compute_pose_quats_and_trans_for_across_views_in_ref_view); move it back into the ARKit world
        pred0 = out[0]["camera_poses"][0].float().cpu().numpy()
        to_world = arkit_to_opencv(episode.frames[indices[0]].pose_arkit) @ np.linalg.inv(pred0)
        result = []
        drift = []
        for i, pred in zip(indices, out, strict=True):
            pts = pred["pts3d"][0].float().cpu().numpy()
            cam2world = to_world @ pred["camera_poses"][0].float().cpu().numpy()
            drift.append(np.linalg.norm(cam2world[:3, 3] - episode.frames[i].pose_arkit[:3, 3]))
            result.append(
                ViewGeometry(
                    index=i,
                    points=pts @ to_world[:3, :3].T + to_world[:3, 3],
                    valid=pred["mask"][0].squeeze(-1).bool().cpu().numpy(),
                    confidence=pred["conf"][0].float().cpu().numpy(),
                    cam2world=cam2world,
                    intrinsics=pred["intrinsics"][0].float().cpu().numpy(),
                    depth=pred["depth_z"][0].squeeze(-1).float().cpu().numpy(),
                )
            )
        log.info("camera drift vs ARKit: median %.3f m, max %.3f m", float(np.median(drift)), float(np.max(drift)))
        return result
