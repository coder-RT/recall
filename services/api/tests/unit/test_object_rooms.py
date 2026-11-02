"""Every remembered thing says which room it is in, also when no furniture is near it."""

from recall_api.application.list_things import ListThings
from recall_api.application.trust import TrustPolicy
from tests.unit.test_matching_and_ingest import ROOM, Repos, obj


def _scanned(things):
    r = Repos()
    r.scan("s1", 10)  # scanned in the "Office"
    r.ingest("s1", {"room": ROOM, "landmarks": [obj("desk", [1.0, 1.0, 0.38])], "objects": things})
    return r, ListThings(r.homes, r.objects, r.scans, TrustPolicy())


def _view(r, things, label):
    return next(v for v in things.all("flat") if v.thing.label == label)


def test_a_thing_by_furniture_takes_the_furnitures_room():
    r, things = _scanned([obj("keys", [1.0, 1.0, 0.8])])
    assert _view(r, things, "keys").room == "Office"


def test_a_thing_far_from_furniture_takes_the_room_it_was_scanned_in():
    r, things = _scanned([obj("bag", [3.8, 2.8, 0.1])])  # more than 1.5 m from the desk
    bag = _view(r, things, "bag")
    assert bag.relation.landmark is None
    assert bag.room == "Office"


def test_found_lists_a_thing_seen_once_but_marks_it_untrusted_and_to_check():
    r, things = _scanned([obj("wallet", [2.0, 2.0, 0.4]) | {"sightings": 1}, obj("keys", [1.0, 1.0, 0.8])])
    wallet, keys = _view(r, things, "wallet"), _view(r, things, "keys")
    assert (wallet.trusted, wallet.needs_review, wallet.where.photos) == (False, True, 1)
    assert (keys.trusted, keys.needs_review) == (True, False)
