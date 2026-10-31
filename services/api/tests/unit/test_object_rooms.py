"""Every remembered thing says which room it is in, also when no furniture is near it."""

from recall_api.adapters.inbound.http.homes import _location
from tests.unit.test_matching_and_ingest import ROOM, Repos, obj


def _scanned(things):
    r = Repos()
    r.scan("s1", 10)  # scanned in the "Office"
    r.ingest("s1", {"room": ROOM, "landmarks": [obj("desk", [1.0, 1.0, 0.38])], "objects": things})
    return r, r.homes.get("flat")


def test_a_thing_by_furniture_takes_the_furnitures_room():
    r, home = _scanned([obj("keys", [1.0, 1.0, 0.8])])
    keys = next(o for o in r.objects.items.values() if o.label == "keys")
    assert _location(keys, home, r.scans).room == "Office"


def test_a_thing_far_from_furniture_takes_the_room_it_was_scanned_in():
    r, home = _scanned([obj("bag", [3.8, 2.8, 0.1])])  # more than 1.5 m from the desk
    bag = next(o for o in r.objects.items.values() if o.label == "bag")
    loc = _location(bag, home, r.scans)
    assert loc.landmark is None
    assert loc.room == "Office"
    assert _location(bag, home).room is None  # without the scans it can't know
