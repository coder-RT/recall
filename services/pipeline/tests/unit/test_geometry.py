import numpy as np

from recall_pipeline.domain.geometry import arkit_to_opencv, column_major_to_matrix, similarity_matrix, umeyama


def rot_z(deg):
    a = np.radians(deg)
    return np.array([[np.cos(a), -np.sin(a), 0], [np.sin(a), np.cos(a), 0], [0, 0, 1]])


def test_column_major_pose_is_read_as_columns():
    T = np.eye(4)
    T[:3, 3] = [1, 2, 3]
    assert np.allclose(column_major_to_matrix(T.T.reshape(-1).tolist()), T)


def test_arkit_to_opencv_keeps_position_and_maps_the_axes():
    T = np.eye(4)
    T[:3, :3] = rot_z(30)
    T[:3, 3] = [0.5, -1.0, 1.4]
    cv = arkit_to_opencv(T)
    assert np.allclose(cv[:3, 3], T[:3, 3])  # same camera centre
    # OpenCV forward (+Z) is ARKit's −Z; OpenCV down (+Y) is ARKit's −Y; right (+X) is unchanged
    assert np.allclose(cv[:3, 2], -T[:3, 2])
    assert np.allclose(cv[:3, 1], -T[:3, 1])
    assert np.allclose(cv[:3, 0], T[:3, 0])
    assert np.isclose(np.linalg.det(cv[:3, :3]), 1.0)  # still a proper rotation


def test_umeyama_recovers_scale_rotation_and_translation():
    rng = np.random.default_rng(0)
    src = rng.normal(size=(50, 3))
    s, R, t = 1.23, rot_z(37) @ np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]]), np.array([0.4, -2.0, 0.7])
    dst = s * src @ R.T + t + rng.normal(scale=1e-4, size=src.shape)
    s2, R2, t2 = umeyama(src, dst)
    assert abs(s2 - s) < 1e-3 and np.allclose(R2, R, atol=1e-3) and np.allclose(t2, t, atol=1e-3)
    M = similarity_matrix(s2, R2, t2)
    assert np.allclose((M @ np.c_[src, np.ones(50)].T).T[:, :3], dst, atol=1e-3)
