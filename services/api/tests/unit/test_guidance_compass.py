"""Guidance gives the phone where to draw its arrow and, with a compass, which way the thing lies."""

from recall_api.application.plan_guidance import PlanGuidance
from tests.fakes import MemoryBlobs
from tests.unit.test_matching_and_ingest import ROOM, Repos, obj

# ARKit (y up) to home (z up), floor at ARKit y = -1.4: the transform the pipeline stores for a scan
T = [1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 1.4, 0, 0, 0, 1]


def _guidance(north_deg):
    r = Repos()
    r.scan("s1", 10)
    r.ingest(
        "s1",
        {
            "room": {**ROOM, "north_deg": north_deg},
            "landmarks": [obj("desk", [3.5, 1.5, 0.38])],
            "objects": [obj("keys", [3.5, 1.5, 0.8])],
            "transform_to_home": T,
        },
    )
    keys = next(o for o in r.objects.items.values() if o.label == "keys")
    g = PlanGuidance(r.homes, r.scans, r.objects, MemoryBlobs(), lambda p: f"{p}1")
    identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    return g.start("flat", keys.id, identity, "limited")


def test_the_arrow_target_is_the_thing_in_the_phones_world():
    out = _guidance(None)
    # home (3.5, 1.5, 0.8) back into ARKit: x stays, ARKit y = z_home - 1.4, ARKit z = -y_home
    assert out["target_arkit"] == [3.5, -0.6, -1.5]
    assert out["floor_y_arkit"] == -1.4  # the floor arrows lie here


def test_bearing_is_magnetic_and_only_when_north_is_known():
    assert _guidance(None)["bearing_deg"] is None
    # the room's centre is (2, 1.5); the keys lie due +x of it. With north along +x, that is north (0 degrees);
    # with north along +y (0 degrees in the home frame), it is east (90 degrees)
    assert _guidance(90.0)["bearing_deg"] == 0.0
    assert _guidance(0.0)["bearing_deg"] == 90.0


def test_a_rescan_that_started_afresh_is_guided_in_its_own_frame():
    # the first scan's floor is at ARKit y = -1.4; a later scan that didn't line up started memory afresh, in a
    # world of its own (floor at y = -1.0); the keys were last seen in that later scan
    r = Repos()
    r.scan("s1", 10)
    r.ingest("s1", {"room": ROOM, "landmarks": [obj("desk", [3.5, 1.5, 0.38])], "objects": [], "transform_to_home": T})
    T2 = [1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 1.0, 0, 0, 0, 1]
    r.scan("s2", 11)
    r.ingest(
        "s2",
        {"room": ROOM, "landmarks": [obj("desk", [1.0, 1.0, 0.38])], "objects": [obj("keys", [1.0, 1.0, 0.8])],
         "transform_to_home": T2},
    )  # fmt: skip
    assert r.scans.get("s2").fresh and r.homes.get("flat").first_scan_id == "s1"
    keys = next(o for o in r.objects.items.values() if o.label == "keys")
    g = PlanGuidance(r.homes, r.scans, r.objects, MemoryBlobs(), lambda p: f"{p}1")
    identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    out = g.start("flat", keys.id, identity, "limited")
    # in the later scan's frame: ARKit y = 0.8 - 1.0, not 0.8 - 1.4 as in the first scan's
    assert out["target_arkit"] == [1.0, -0.2, -1.0]
    assert out["floor_y_arkit"] == -1.0
    assert g.sessions[out["session_id"]].scan_id == "s2"
    assert out["steps"][0]["say"].startswith("Your keys are ")  # plural, not "keys is"
