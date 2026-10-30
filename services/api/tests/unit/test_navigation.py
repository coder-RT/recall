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
