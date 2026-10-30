from datetime import UTC, datetime

from recall_api.application.ingest_scan import IngestScan
from recall_api.domain.memory import Home, Position, Scan, ScanStatus
from recall_api.domain.memory.matching import match_label
from tests.fakes import FixedClock, MemoryRepo

ROOM = {"floor_polygon": [[0, 0], [4, 0], [4, 3], [0, 3]], "walls": [], "furniture": [], "height_m": 2.5}


def test_assignment_tells_same_moved_new_and_gone_apart():
    old = [Position(1, 1, 0.8), Position(3, 1, 0.8)]  # two mugs remembered
    new = [Position(1.05, 1, 0.8), Position(3, 2.5, 0.8), Position(0.5, 2.8, 0.4)]  # one stayed, one moved, a third
    m = {(x.existing, x.detected): x.kind for x in match_label(old, new, covered=lambda p: True)}
    assert m[(0, 0)] == "same" and m[(1, 1)] == "moved" and m[(None, 2)] == "new"


def test_an_object_not_seen_where_the_scan_looked_is_gone_but_elsewhere_it_stands():
    old = [Position(1, 1, 0.8), Position(9, 9, 0.8)]
    kinds = {x.existing: x.kind for x in match_label(old, [], covered=lambda p: p.x < 5)}
    assert kinds == {0: "gone", 1: "out_of_view"}


class Repos:
    def __init__(self):
        self.scans, self.homes, self.objects = MemoryRepo(), MemoryRepo(), MemoryRepo()
        self.homes.save(Home(id="flat", name="flat"))
        n = iter(range(1000))
        self.ingest = IngestScan(self.scans, self.homes, self.objects, FixedClock(), lambda p: f"{p}{next(n)}")

    def scan(self, sid, hour):
        s = Scan(id=sid, home_id="flat", room="Office", status=ScanStatus.PROCESSING, archive_size=1,
                 archive_sha256="x", part_size=5242880, created_at=datetime(2026, 10, 30, hour, tzinfo=UTC))
        self.scans.save(s)
        return s


def obj(label, c, conf=0.9):
    return {"label": label, "centroid": c, "bbox_min": c, "bbox_max": c, "confidence": conf, "sightings": 3}


def test_two_scans_one_object_moved_and_one_disappeared():
    r = Repos()
    r.scan("s1", 10)
    r.ingest("s1", {"room": ROOM, "landmarks": [obj("desk", [2, 1, 0.38])],
                    "objects": [obj("keys", [1, 1, 0.8]), obj("mug", [3, 2, 0.8])]})
    r.scan("s2", 12)
    done = r.ingest("s2", {"room": ROOM, "landmarks": [], "objects": [obj("keys", [2, 2.5, 0.8])]})
    assert done.status == ScanStatus.PROCESSED and "1 moved" in done.detail and "1 gone" in done.detail
    keys = next(o for o in r.objects.items.values() if o.label == "keys")
    mug = next(o for o in r.objects.items.values() if o.label == "mug")
    assert keys.last_seen().position == Position(2, 2.5, 0.8) and keys.last_seen().scan_id == "s2"
    assert mug.last_seen() is None  # gone: not where it was, so memory no longer claims it
    assert [lm.label for lm in r.homes.get("flat").landmarks] == ["desk"]
