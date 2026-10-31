import numpy as np

from recall_pipeline.domain import home_frame, room_model
from recall_pipeline.domain.lift import lift_box

K = np.array([[500.0, 0, 320], [0, 500.0, 240], [0, 0, 1]])


def test_a_box_on_flat_depth_lifts_to_the_right_point():
    depth = np.full((480, 640), 2.0, np.float32)
    lifted = lift_box((300, 220, 340, 260), depth, K, np.eye(4))
    assert lifted is not None
    assert np.allclose(lifted.centroid, [0.0, 0.0, 2.0], atol=0.01)


def test_background_behind_the_object_is_ignored():
    depth = np.full((480, 640), 3.0, np.float32)
    depth[225:255, 305:335] = 1.0  # the object fills the middle of its box; the wall behind is 2 m further
    lifted = lift_box((300, 220, 340, 260), depth, K, np.eye(4))
    assert abs(lifted.depth_m - 1.0) < 0.01


def test_no_depth_means_no_lift():
    assert lift_box((300, 220, 340, 260), np.zeros((480, 640), np.float32), K, np.eye(4)) is None


def test_arkit_y_up_becomes_z_up_with_the_floor_at_zero():
    T = home_frame.to_home(floor_height_arkit_y=-1.4)  # the floor is 1.4 m below the session origin
    p = home_frame.apply(T, np.array([[0.5, -1.4, -2.0]]))  # a point on the floor, 2 m in front
    assert np.allclose(p, [[0.5, 2.0, 0.0]])


def test_room_json_from_a_synthetic_rectangular_room():
    rng = np.random.default_rng(1)
    floor = np.c_[rng.uniform(0, 4, 4000), rng.uniform(0, 3, 4000), np.zeros(4000)]
    wall_pts = np.c_[rng.uniform(0, 4, 2000), np.full(2000, 3.0), rng.uniform(0, 2.5, 2000)]
    wall = room_model.WallPlane(np.array([0.0, 1.0, 0.0]), -3.0, wall_pts)
    desk = np.c_[rng.uniform(1, 2.2, 500), rng.uniform(0.2, 0.8, 500), rng.uniform(0, 0.76, 500)]
    room = room_model.room_json(room_model.floor_polygon(floor), [wall], [("desk", desk)])
    xs = [p[0] for p in room["floor_polygon"]]
    ys = [p[1] for p in room["floor_polygon"]]
    assert min(xs) < 0.1 and max(xs) > 3.9 and min(ys) < 0.1 and max(ys) > 2.9
    (ax, ay), (bx, by) = room["walls"][0]["start"], room["walls"][0]["end"]
    assert abs(ay - 3.0) < 0.05 and abs(by - 3.0) < 0.05 and abs(abs(bx - ax) - 4.0) < 0.2
    assert abs(room["furniture"][0]["top_z"] - 0.76) < 0.03
