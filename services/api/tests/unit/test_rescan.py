"""Rescans: memory is per room, a recognised rescan says what changed, an unrecognised one starts the room afresh."""

from recall_api.domain.memory import ScanChange, ScanStatus
from tests.unit.test_matching_and_ingest import ROOM, Repos, obj


def box(label, lo, hi):
    return {
        "label": label,
        "centroid": [(a + b) / 2 for a, b in zip(lo, hi, strict=True)],
        "bbox_min": lo,
        "bbox_max": hi,
        "confidence": 0.9,
        "sightings": 3,
    }


DESK = box("desk", [0.6, 0.7, 0.0], [1.4, 1.3, 0.76])  # top at 0.76 m
SHELF = box("shelf", [2.7, 1.8, 0.0], [3.3, 2.2, 0.9])  # top at 0.9 m


def _first(r: Repos, room="Office"):
    r.scan("s1", 10, room=room)
    r.ingest(
        "s1",
        {
            "room": ROOM,
            "landmarks": [DESK, SHELF],
            "objects": [obj("keys", [1.0, 1.0, 0.8]), obj("bag", [1.2, 1.0, 0.3])],
        },
    )


def test_a_recognised_rescan_lists_moved_new_and_gone_in_words():
    r = Repos()
    _first(r)
    first = r.scans.get("s1")
    assert first.changes == [] and not first.fresh  # a room's first scan: nothing to compare with
    r.scan("s2", 12, aligned_to="s1")
    done = r.ingest(
        "s2",
        {
            "room": ROOM,
            "landmarks": [DESK, SHELF],
            "objects": [obj("keys", [3.0, 2.0, 0.95]), obj("mug", [1.0, 1.0, 0.8])],
        },
    )
    assert done.status == ScanStatus.PROCESSED and not done.fresh
    by_kind = {c.kind: c for c in done.changes}
    keys = by_kind["moved"]
    assert (keys.label, keys.from_place) == ("keys", "on the desk")
    assert keys.to_place.endswith("the shelf")
    assert by_kind["new"] == ScanChange("new", by_kind["new"].object_id, "mug", None, None, None, "on the desk")
    assert (by_kind["gone"].label, by_kind["gone"].from_place, by_kind["gone"].to_place) == (
        "bag",
        "near the desk",
        None,
    )
    assert len(done.changes) == 3  # nothing listed for what stayed put


def test_another_room_leaves_this_rooms_things_alone():
    r = Repos()
    _first(r, room="Living room")
    r.scan("s2", 12, room="Kitchen")
    done = r.ingest("s2", {"room": ROOM, "landmarks": [], "objects": [obj("mug", [1.0, 1.0, 0.8])]})
    assert "gone" not in (done.detail or "")
    living = [o for o in r.objects.items.values() if o.label in ("keys", "bag")]
    assert all(o.where() is not None for o in living)  # still remembered where they were
    assert done.changes == [] and not done.fresh  # the kitchen's first scan
    assert {lm.room for lm in r.homes.get("flat").landmarks} == {"Living room"}


def test_an_unrecognised_rescan_starts_the_room_afresh():
    r = Repos()
    _first(r)
    r.scan("s2", 12)  # same room, but the phone didn't recognise it: no shared frame
    done = r.ingest("s2", {"room": ROOM, "landmarks": [SHELF], "objects": [obj("keys", [3.0, 2.0, 0.95])]})
    assert done.fresh and done.changes == []
    keys = [o for o in r.objects.items.values() if o.label == "keys"]
    assert [o.where() is not None for o in keys].count(True) == 1  # only the new sighting counts
    assert next(o for o in r.objects.items.values() if o.label == "bag").where() is None
    assert [lm.label for lm in r.homes.get("flat").landmarks] == ["shelf"]  # the old desk is gone with the frame
