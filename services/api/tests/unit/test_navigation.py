import math

import numpy as np
import pytest

from recall_api.domain.navigation import FloorGrid, NavConfig, NoSafePath, plan, simplify, to_clock_steps
from recall_api.domain.navigation.route import clock

CFG = NavConfig()


def corridor(width_m: float, length_m: float = 4.0) -> FloorGrid:
    """A corridor along +x: walls (blocked) above and below a free strip `width_m` wide."""
    cells_w = int(round(width_m / CFG.cell_m))
    h, w = cells_w + 4, int(length_m / CFG.cell_m)
    raw = np.ones((h, w), bool)
    raw[2 : 2 + cells_w, :] = False
    return FloorGrid.from_blocked(raw, (0.0, 0.0), CFG)


def test_the_route_keeps_to_the_middle_of_a_corridor():
    g = corridor(1.6)
    mid = 0.2 + 0.8  # free strip starts at y = 0.2 m and is 1.6 m wide
    path = plan(g, (0.5, mid - 0.4), (3.5, mid + 0.4))
    ys = [p[1] for p in path[3:-3]]
    assert max(abs(y - mid) for y in ys) <= 0.25


def test_a_gap_narrower_than_a_body_has_no_safe_path():
    with pytest.raises(NoSafePath):
        plan(corridor(0.5), (0.5, 0.45), (3.5, 0.45))


def room_cloud(seen_floor_x_max: float) -> np.ndarray:
    """A 4 x 2 m room: walls of points along y = 0 and y = 2 (0.1 to 1.5 m high), floor points only where x is
    below `seen_floor_x_max` (the camera never looked down further along)."""
    xs = np.arange(0.0, 4.0, 0.05)
    walls = [(x, y, z) for x in xs for y in (0.0, 2.0) for z in np.arange(0.1, 1.5, 0.1)]
    floor = [(x, y, 0.0) for x in xs if x < seen_floor_x_max for y in np.arange(0.2, 1.85, 0.05)]
    return np.array(walls + floor)


def test_floor_nobody_saw_is_not_entered():
    g = FloorGrid.from_points(room_cloud(1.5))
    with pytest.raises(NoSafePath):
        plan(g, (0.5, 1.0), (3.5, 1.0))


def test_the_walked_path_counts_as_floor():
    walked = np.array([(x, 1.0) for x in np.arange(0.3, 3.8, 0.1)])
    g = FloorGrid.from_points(room_cloud(1.5), walked=walked)
    path = plan(g, (0.5, 1.0), (3.5, 1.0))
    assert path[-1][0] > 3.2


def test_one_stray_point_is_not_a_wall():
    cloud = np.vstack([room_cloud(4.0), [(2.0, 1.0, 1.0)]])  # a single floater in the middle of the room
    g = FloorGrid.from_points(cloud)
    assert not g.blocked[g.cell_of(2.0, 1.0)]


def test_simplify_keeps_only_the_corner():
    pts = [(x / 10, 0.0) for x in range(11)] + [(1.0, y / 10) for y in range(1, 11)]
    assert simplify(pts) == [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0)]


def test_clock_faces():
    assert clock((1, 0), (1, 0)) == 12
    assert clock((1, 0), (0, -1)) == 3  # z up: −y is to the right of +x
    assert clock((1, 0), (0, 1)) == 9
    assert clock((1, 0), (-1, 0)) == 6
    assert clock((1, 0), (math.cos(math.radians(-30)), math.sin(math.radians(-30)))) == 1


def test_steps_are_spoken_as_turns_and_metres():
    steps = to_clock_steps([(0, 0), (2, 0), (2, -1.5)], heading_xy=(1, 0))
    assert [s["clock"] for s in steps] == [12, 3]
    assert steps[0]["say"] == "Straight ahead, then about 2 metres." and steps[1]["metres"] == 1.5
