import math
import xml.etree.ElementTree as ET

import numpy as np
from shapely import contains_xy
from shapely.geometry import Polygon

from recall_pipeline.domain import architecture as arch
from recall_pipeline.domain import drawings


def _room_points(theta: float, notch: bool = False, seed: int = 0) -> np.ndarray:
    """Points of an L-shaped (or plain) 5 x 4 m room's floor and walls, rotated by theta, with 2 cm noise."""
    rng = np.random.default_rng(seed)
    outline = [(0, 0), (5, 0), (5, 4), (0, 4)] if not notch else [(0, 0), (5, 0), (5, 2.5), (3, 2.5), (3, 4), (0, 4)]
    poly = Polygon(outline)
    xy = rng.uniform([0, 0], [5, 4], size=(20000, 2))
    xy = xy[contains_xy(poly, xy[:, 0], xy[:, 1])]
    xy = arch.rotate(xy + rng.normal(0, 0.02, xy.shape), theta)
    return xy


def test_manhattan_angle_finds_the_walls_direction():
    theta = math.radians(23)
    walls = []
    for a, b in [((0, 0), (5, 0)), ((5, 0), (5, 4)), ((5, 4), (0, 4))]:
        pa, pb = arch.rotate(np.array([a, b], float), theta)
        walls.append((tuple(pa), tuple(pb)))
    assert abs(math.degrees(arch.manhattan_angle(walls)) - 23) < 1.0


def test_plan_of_a_noisy_l_shaped_room_is_rectilinear_and_close_in_area():
    theta = math.radians(17)
    plan = arch.plan_outline(_room_points(theta, notch=True), theta)
    ring = np.array(plan.exterior.coords)[:-1]
    edges = np.roll(ring, -1, axis=0) - ring
    assert np.all(np.isclose(edges, 0, atol=1e-6).any(axis=1))  # every edge is horizontal or vertical
    assert len(ring) == 6
    assert abs(plan.area - 16.0) / 16.0 < 0.05  # 5 x 4 minus the 2 x 1.5 notch


def test_walls_the_scan_never_saw_are_marked_unscanned():
    plan = Polygon([(0, 0), (5, 0), (5, 4), (0, 4)])
    measured = [(np.array([0.2, 0.05]), np.array([4.8, 0.08]))]  # only the bottom wall was seen
    walls = arch.walls_of(plan, measured)
    assert [w.scanned for w in walls].count(True) == 1
    seen = next(w for w in walls if w.scanned)
    assert {seen.a[1], seen.b[1]} == {0.0}


def test_a_door_becomes_an_opening_in_its_nearest_wall():
    walls = arch.walls_of(Polygon([(0, 0), (5, 0), (5, 4), (0, 4)]), [])
    arch.place_door(walls, np.array([2.0, -0.05, 0.0]), np.array([2.9, 0.05, 2.0]))
    opened = [w for w in walls if w.openings]
    assert len(opened) == 1 and opened[0].a[1] == opened[0].b[1] == 0.0
    door = opened[0].openings[0]
    assert abs(door["width"] - 0.9) < 1e-6 and 1.9 < door["offset"] + door["width"] / 2 < 2.6


def test_furniture_becomes_parts_of_its_kind():
    lo, hi, centre = np.array([0, 0, 0]), np.array([1.2, 0.6, 0.75]), np.array([3, 3])
    desk = arch.furniture_parts("desk", lo, hi, centre)
    assert [p.kind for p in desk].count("leg") == 4 and desk[0].kind == "top"
    assert abs(desk[0].centre[2] + desk[0].size[2] / 2 - 0.75) < 1e-6  # the top is at the measured height
    shelf = arch.furniture_parts("shelf", lo, np.array([0.8, 0.3, 1.8]), centre)
    assert [p.kind for p in shelf].count("board") >= 5 and [p.kind for p in shelf].count("side") == 2
    tv = arch.furniture_parts("tv", np.array([0, 0, 1]), np.array([1.0, 0.2, 1.6]), np.array([0.5, 3.0]))
    assert len(tv) == 1 and tv[0].centre[1] < 0.1  # the panel stands at the back, away from the room


def test_floor_plan_sheet_dimensions_every_wall_and_lists_every_thing():
    plan = Polygon([(0, 0), (4.25, 0), (4.25, 3.1), (0, 3.1)])
    walls = arch.walls_of(plan, [(np.array([0.1, 0.0]), np.array([4.1, 0.0]))])
    items = [
        drawings.Item(1, "red keys", "on the desk, waist height", (1, 1, 0.75)),
        drawings.Item(2, "grey bag", "near the desk, knee height", (2, 2, 0.4)),
    ]
    sheet = drawings.plan_sheet(
        plan,
        walls,
        [drawings.Furnishing("desk", (0.5, 0.5, 0), (1.7, 1.1, 0.75))],
        items,
        "Living room",
        "2026-10-30",
        2.5,
        0.0,
        "Measured.",
    )
    root = ET.fromstring(sheet.svg)
    texts = [t.text for t in root.iter("{http://www.w3.org/2000/svg}text")]
    assert texts.count("4.25") >= 2 and texts.count("3.10") >= 2  # each wall's dimension, both of each pair
    assert any("red keys" in t for t in texts) and any("grey bag" in t for t in texts)
    assert "A1.1" in texts and "Living room" in texts


def test_elevation_shows_the_wall_from_inside_nearest_first():
    wall = arch.Wall((0.0, 0.0), (2.0, 0.0), True)
    # a red point on the wall and a blue one 0.3 m in front of it, at the same spot: the wall's own point is hidden
    pts = np.array([[1.0, 0.0, 1.0], [1.0, 0.3, 1.0]])
    rgb = np.array([[255, 0, 0], [0, 0, 255]], dtype=np.float32)
    img = drawings.elevation_raster(pts, rgb, wall, 2.0)
    assert img.shape == (200, 200, 3)
    assert tuple(img[100, 100]) == (255, 0, 0)  # nearest to the wall wins


def test_magnetic_north_turns_into_the_home_frame_and_labels_the_plan():
    from recall_pipeline.domain.home_frame import north_in_home, to_home

    T = to_home(-1.4)
    # facing +X in ARKit (yaw 90) is +x in the home frame: 90 degrees clockwise from +y
    assert north_in_home(T, 90.0, 5.0) == 90.0
    assert north_in_home(T, 90.0, 40.0) is None  # too scattered to trust
    assert north_in_home(T, None, None) is None
    plan = Polygon([(0, 0), (4, 0), (4, 3), (0, 3)])
    walls = arch.walls_of(plan, [])
    svg = drawings.plan_sheet(plan, walls, [], [], "Room", "2026-10-31", 2.5, 0.0, "x", north_deg=90.0).svg
    assert "magnetic north" in svg and "scan north" not in svg


def test_a_long_list_of_things_stays_left_of_the_title_block():
    plan = Polygon([(0, 0), (3.5, 0), (3.5, 7.4), (0, 7.4)])
    walls = arch.walls_of(plan, [])
    items = [drawings.Item(i + 1, f"grey thing {i + 1}", "near the desk, waist height", (1, 1, 0.8)) for i in range(28)]
    root = ET.fromstring(drawings.plan_sheet(plan, walls, [], items, "Room", "2026-11-01", 2.5, 0.0, "x").svg)
    listed = [t for t in root.iter("{http://www.w3.org/2000/svg}text") if (t.text or "").endswith("waist height")]
    assert len(listed) == 28
    x1 = drawings.AREA[2]
    # each line starts a column that ends before the title block (columns are a third of the legend's width)
    col_w = (x1 - (drawings.AREA[0] + 60)) / 3
    assert all(float(t.get("x")) + col_w <= x1 + 0.01 for t in listed)
    assert max(float(t.get("y")) for t in listed) <= drawings.AREA[3]
