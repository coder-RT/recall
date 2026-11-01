"""Only what was seen more than once is told: a thing in one photo waits for the owner, a confirmed thing always
counts, and "Not there" keeps the same mistake from coming back on the next scan."""

from datetime import UTC, datetime

from recall_api.application.correct_object import CorrectObject
from recall_api.application.trust import TrustPolicy
from recall_api.domain.memory import Observation, Position, Rejection, TrackedObject, Trust
from tests.fakes import FixedClock
from tests.unit.test_matching_and_ingest import ROOM, Repos, obj

T = datetime(2026, 11, 1, 5, 45, tzinfo=UTC)


def _thing(photos: int | None, conf: float = 0.8, confirmed: bool = False) -> TrackedObject:
    o = TrackedObject("obj_1", "flat", "wallet")
    o.observations.append(Observation("obs_1", "obj_1", "s1", T, Position(1.0, 2.0, 0.4), conf, photos=photos))
    o.corrections.confirmed = confirmed
    return o


class Settings:
    def __init__(self) -> None:
        self.values: dict[str, str] = {}

    def get(self, key):
        return self.values.get(key)

    def put(self, key, value):
        self.values[key] = value


def test_each_level_asks_for_its_number_of_photos():
    assert [t.min_photos for t in (Trust.CAREFUL, Trust.BALANCED, Trust.EVERYTHING)] == [3, 2, 1]


def test_a_thing_seen_once_waits_unless_the_owner_wants_everything():
    once = _thing(photos=1)
    assert once.where(Trust.BALANCED) is None
    assert once.where(Trust.EVERYTHING) is not None
    assert once.needs_review(Trust.BALANCED)


def test_a_thing_seen_from_several_places_is_told():
    seen = _thing(photos=3)
    assert seen.where(Trust.CAREFUL) is not None
    assert not seen.needs_review(Trust.CAREFUL)


def test_a_confirmed_thing_always_counts():
    yes = _thing(photos=1, conf=0.3, confirmed=True)
    assert yes.where(Trust.CAREFUL) is not None
    assert not yes.needs_review(Trust.CAREFUL)


def test_sightings_kept_before_photos_were_counted_still_count():
    assert _thing(photos=None).where(Trust.CAREFUL) is not None


def test_unsure_things_ask_for_a_check_even_when_seen_often():
    assert _thing(photos=10, conf=0.6).needs_review(Trust.BALANCED)


def test_the_level_defaults_to_balanced_and_is_kept_on_the_mac():
    settings = Settings()
    policy = TrustPolicy(settings)
    assert policy.level is Trust.BALANCED
    assert policy.set(Trust.CAREFUL) is Trust.CAREFUL
    assert settings.values == {"trust": "careful"}
    settings.values["trust"] = "paranoid"  # from some other build
    assert policy.level is Trust.BALANCED


def test_a_rejection_covers_the_same_kind_of_thing_nearby_unless_clearly_seen():
    no = Rejection("rej_1", "wallet", Position(1.0, 2.0, 0.4), T)
    assert no.covers("Wallet", Position(1.3, 2.0, 0.4), photos=1)
    assert not no.covers("wallet", Position(2.0, 2.0, 0.4), photos=1)  # a metre away: another place
    assert not no.covers("mug", Position(1.0, 2.0, 0.4), photos=1)
    assert not no.covers("wallet", Position(1.0, 2.0, 0.4), photos=6)  # seen clearly: someone put one there


def test_not_there_keeps_the_mistake_away_on_the_next_scan():
    r = Repos()
    r.objects.save(_thing(photos=1))
    CorrectObject(r.objects, r.homes, FixedClock(), lambda prefix: f"{prefix}_1").remove("flat", "obj_1")
    assert r.objects.get("obj_1") is None
    assert [x.label for x in r.homes.get("flat").rejections] == ["wallet"]

    r.scan("s2", 12)
    wallet = obj("wallet", [1.1, 2.0, 0.4], conf=0.55) | {"sightings": 1}  # the same mistake, a little apart
    done = r.ingest("s2", {"room": ROOM, "landmarks": [], "objects": [wallet, obj("mug", [0.5, 0.5, 0.8])]})
    assert [o.label for o in r.objects.items.values()] == ["mug"]
    assert done.object_count == 1 and "1 not there" in done.detail
