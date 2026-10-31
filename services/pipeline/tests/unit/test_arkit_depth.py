import numpy as np
import pytest

from recall_pipeline.adapters.arkit_depth import ArkitDepth
from recall_pipeline.adapters.run import make_reconstructor
from recall_pipeline.domain.episode import Episode, FrameRecord, Intrinsics
from recall_pipeline.domain.geometry import arkit_to_opencv, backproject, scale_intrinsics


def test_backproject_inverts_the_pinhole_projection():
    K = np.array([[500.0, 0, 320], [0, 500, 240], [0, 0, 1]])
    T = np.eye(4)
    T[:3, 3] = [1.0, 2.0, 3.0]
    depth = np.full((480, 640), 2.0)
    pts = backproject(depth, K, T)
    cam = pts[100, 200] - T[:3, 3]
    u, v = K[0, 0] * cam[0] / cam[2] + K[0, 2], K[1, 1] * cam[1] / cam[2] + K[1, 2]
    assert np.allclose([u, v], [200.5, 100.5]) and np.isclose(cam[2], 2.0)


def test_scale_intrinsics_halves_focal_and_centre():
    K = np.array([[800.0, 0, 512], [0, 800, 384], [0, 0, 1]])
    assert np.allclose(scale_intrinsics(K, 0.5, 0.5), [[400, 0, 256], [0, 400, 192], [0, 0, 1]])


class WallSource:
    """A flat wall 2 m in front of the camera; one corner has no LiDAR return."""

    def depth_m(self, index, size):
        d = np.full((size[1], size[0]), 2.0, dtype=np.float32)
        d[:10, :10] = 0.0
        return d


def episode(pose):
    return Episode(
        "s", (1024, 768), (256, 192), Intrinsics(800, 800, 512, 384), (FrameRecord(0, 0.0, pose, "normal", None),), None
    )


def test_arkit_depth_puts_a_wall_in_front_of_the_camera_in_the_arkit_world():
    pose = np.eye(4)
    pose[:3, 3] = [0.5, 1.4, -1.0]  # ARKit camera looks along world −Z
    (v,) = ArkitDepth().reconstruct(episode(pose), WallSource(), [0])
    assert v.points.shape[:2] == v.depth.shape == (384, 512)  # long edge 512
    assert not v.valid[:5, :5].any() and v.valid[200:, 200:].all()
    centre = v.points[192, 256]
    assert np.allclose(centre, [0.5, 1.4, -3.0], atol=0.01)  # 2 m ahead, metric, no model
    assert np.allclose(v.cam2world, arkit_to_opencv(pose))
    assert np.allclose(v.intrinsics[0, 0], 400)


def test_reconstructor_choice():
    assert isinstance(make_reconstructor({"RECONSTRUCTOR": "arkit_depth"}), ArkitDepth)
    with pytest.raises(ValueError):
        make_reconstructor({"RECONSTRUCTOR": "vggt"})
