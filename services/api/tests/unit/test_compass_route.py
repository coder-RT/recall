"""The Watch walks by compass: legs of a magnetic bearing and metres, from where the room's scan began."""

import io
import json

import numpy as np
import pytest

from recall_api.application.plan_compass_route import CompassRouteError, PlanCompassRoute
from recall_api.domain.navigation import bearing, compass_legs
from tests.fakes import MemoryBlobs
from tests.unit.test_matching_and_ingest import Repos, obj


def test_bearings_are_clockwise_from_magnetic_north():
    assert bearing(0, 1, 0) == 0  # +y is north when north_deg is 0
    assert bearing(1, 0, 0) == 90
    assert bearing(0, 1, 90) == 270  # north lies along +x: +y is west
    assert bearing(-1, 0.001, 0) == pytest.approx(270, abs=0.2)
    assert 0 <= bearing(0.001, 1, 359) < 360  # wraps, never negative


def test_a_corner_makes_two_legs_and_tiny_ones_are_folded_away():
    legs = compass_legs([(0, 0), (0, 2), (0, 2.1), (2, 2.1)], north_deg=0)
    assert [round(leg["bearing_deg"]) for leg in legs] == [0, 90]
    assert [leg["metres"] for leg in legs] == [2.0, 2.0]


def _room(north_deg):
    r = Repos()
    room = {"floor_polygon": [[0, 0], [4, 0], [4, 3], [0, 3]], "walls": [], "furniture": [], "height_m": 2.5}
    if north_deg is not None:
        room["north_deg"] = north_deg
    r.scan("s1", 10)
    r.ingest("s1", {"room": room, "landmarks": [], "objects": [obj("keys", [3.0, 2.0, 0.8])]})
    scan = r.scans.get("s1")
    scan.transform_to_home = tuple(np.eye(4).reshape(-1))
    r.scans.save(scan)
    xs, ys = np.meshgrid(np.arange(0.0, 4.0, 0.05), np.arange(0.0, 3.0, 0.05))
    floor = np.c_[xs.ravel(), ys.ravel(), np.zeros(xs.size)]
    blobs = MemoryBlobs()
    buf = io.BytesIO()
    np.save(buf, floor)
    blobs.put(f"{scan.folder}/episode/home_cloud.npy", buf.getvalue())
    pose = np.eye(4)
    pose[:3, 3] = [0.5, 0.5, 0.0]  # the scan began here
    blobs.put(f"{scan.folder}/episode/poses.jsonl", (json.dumps({"pose": pose.T.reshape(-1).tolist()}) + "\n").encode())
    keys = next(o for o in r.objects.items.values() if o.label == "keys")
    return PlanCompassRoute(r.homes, r.scans, r.objects, blobs), keys.id


def test_the_walk_starts_where_the_scan_began_and_heads_for_the_thing():
    route, keys = _room(north_deg=90)
    r = route("flat", keys)
    assert r.label == "keys" and r.start == "where you started the scan of Office"
    total = sum(leg["metres"] for leg in r.legs)
    assert total == pytest.approx(2.9, abs=0.5)  # (0.5, 0.5) to near (3.0, 2.0)
    # straight there is atan2(2.5, 1.5) = 59° from +y; north along +x makes that 329° magnetic
    first = r.legs[0]["bearing_deg"]
    assert min(abs(first - 329), 360 - abs(first - 329)) < 25


def test_without_a_compass_the_room_must_be_scanned_again():
    route, keys = _room(north_deg=None)
    with pytest.raises(CompassRouteError) as e:
        route("flat", keys)
    assert e.value.code == "no_compass" and e.value.status == 409
