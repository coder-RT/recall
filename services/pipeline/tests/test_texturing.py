import numpy as np

from recall_pipeline.domain import texturing as tx

K = np.array([[500.0, 0, 320], [0, 500.0, 240], [0, 0, 1]])


def _camera(position, look_at, depth=None) -> tx.Camera:
    """An OpenCV camera at `position` looking at `look_at` (+Z forward, +Y down; world z is up)."""
    pos, target = np.array(position, float), np.array(look_at, float)
    z = target - pos
    z /= np.linalg.norm(z)
    x = np.cross(z, [0, 0, 1.0])
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    c2w = np.eye(4)
    c2w[:3, :3] = np.column_stack([x, y, z])
    c2w[:3, 3] = pos
    return tx.Camera(K, c2w, 640, 480, depth)


def _wall():
    """A 2 x 2 m wall in the plane y = 0, two triangles."""
    v = np.array([[-1, 0, 0], [1, 0, 0], [1, 0, 2], [-1, 0, 2]], float)
    return v, np.array([[0, 1, 2], [0, 2, 3]])


def test_each_triangle_takes_the_frontal_photo():
    v, t = _wall()
    frontal = _camera((0, -3, 1), (0, 0, 1))
    oblique = _camera((-2.5, -1.2, 1), (0, 0, 1))
    tm = tx.texture(v, t, np.full((4, 3), 128, np.uint8), [oblique, frontal])
    assert tm.frames == [1] and tm.textured_share == 1.0
    assert np.all((tm.uvs >= 0) & (tm.uvs <= 1))


def test_a_photo_with_something_in_front_does_not_texture_the_wall():
    v, t = _wall()
    blocked = np.full((48, 64), 1.0, np.float32)  # LiDAR saw something 1 m away, in front of a wall 3 m away
    near_but_blocked = _camera((0, -3, 1), (0, 0, 1), depth=blocked)
    other = _camera((0.8, -3.5, 1.2), (0, 0, 1))
    tm = tx.texture(v, t, np.zeros((4, 3), np.uint8), [near_but_blocked, other])
    assert tm.frames == [1]


def test_unseen_triangles_keep_their_vertex_colours():
    v, t = _wall()
    behind = _camera((0, 3, 1), (0, 6, 1))  # looks away from the wall
    tm = tx.texture(v, t, np.full((4, 3), 200, np.uint8), [behind])
    assert len(tm.index) == 0 and len(tm.rest_index) == 2 and tm.textured_share == 0.0


def test_exposure_gains_are_clamped():
    gains = tx.exposure_gains(np.array([50.0, 100.0, 400.0]))
    assert np.allclose(gains, [1.4, 1.0, 0.7])


def test_neighbours_link_triangles_across_shared_edges():
    nb = tx.neighbours(np.array([[0, 1, 2], [0, 2, 3]]))
    assert 1 in nb[0] and 0 in nb[1]
