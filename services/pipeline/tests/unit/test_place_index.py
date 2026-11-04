import numpy as np

from recall_pipeline.domain.place_index import depth_at, lift_keypoints


def test_keypoints_lift_onto_a_wall_in_front_of_an_arkit_camera():
    # ARKit camera at (1, 1.5, 0) looking down −z at a wall 2 m away; the image is 4x the depth map
    K = np.array([[700.0, 0, 512], [0, 700.0, 384], [0, 0, 1]])
    depth = np.full((192, 256), 2000, np.uint16)
    pose = np.eye(4)
    pose[:3, 3] = [1.0, 1.5, 0.0]
    uv = np.array([[512.0, 384.0], [862.0, 384.0], [512.0, 34.0]])
    xyz, keep = lift_keypoints(uv, depth, K, (1024, 768), pose)
    assert list(keep) == [0, 1, 2]
    # straight ahead; 350 px right = 1 m right; 350 px up (smaller v) = 1 m up (ARKit +y)
    assert np.allclose(xyz, [[1.0, 1.5, -2.0], [2.0, 1.5, -2.0], [1.0, 2.5, -2.0]])


def test_missing_depth_borrows_a_neighbour_and_out_of_range_is_dropped():
    depth = np.zeros((10, 10), np.uint16)
    depth[5, 6] = 1500  # one valid pixel next to the asked one
    depth[0, 0] = 9000  # 9 m: past LiDAR's range
    z = depth_at(depth, np.array([[5.2, 5.2], [0.1, 0.1], [9.0, 9.0]]))
    assert z[0] == 1.5 and np.isnan(z[1]) and np.isnan(z[2])
