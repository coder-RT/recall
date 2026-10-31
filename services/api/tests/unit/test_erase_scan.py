"""Erase a scan from the Mac: its files go, and memory goes back to what the room's other scans say."""

import pytest
from fastapi.testclient import TestClient

from recall_api.application.erase_scan import EraseError, EraseScan
from recall_api.domain.audit import Action
from recall_api.domain.memory import Scan
from tests.fakes import MemoryBlobs
from tests.unit.test_matching_and_ingest import ROOM, Repos, obj
from tests.unit.test_rescan import DESK, SHELF


class Audit:
    def __init__(self):
        self.events = []

    def __call__(self, action, actor, *args, **detail):
        self.events.append((action, detail))


def two_scans():
    """s1: keys on the desk, a bag. s2 (recognised): keys moved to the shelf, a new mug, the bag gone."""
    r = Repos()
    r.scan("s1", 10)
    r.ingest("s1", {"room": ROOM, "landmarks": [DESK, SHELF],
                    "objects": [obj("keys", [1.0, 1.0, 0.8]), obj("bag", [1.2, 1.0, 0.3])]})  # fmt: skip
    r.scan("s2", 12, aligned_to="s1")
    r.ingest("s2", {"room": ROOM, "landmarks": [DESK, SHELF],
                    "objects": [obj("keys", [3.0, 2.0, 0.95]), obj("mug", [1.0, 1.0, 0.8])]})  # fmt: skip
    blobs, audit = MemoryBlobs(), Audit()
    for s in ("s1", "s2"):
        blobs.put(f"{r.scans.get(s).folder}/episode/frames/000001.jpg", b"photo")
    erase = EraseScan(r.scans, r.homes, r.objects, blobs, audit=audit)
    return r, blobs, audit, erase


def where(r, label):
    found = [o.where() for o in r.objects.list_for_home("flat") if o.label == label and o.where()]
    return tuple(found[0].position.as_tuple()) if found else None


def test_erasing_the_newest_scan_puts_the_room_back_as_the_earlier_scan_saw_it():
    r, blobs, audit, erase = two_scans()
    folder = r.scans.get("s2").folder
    done = erase("s2")
    assert where(r, "keys") == (1.0, 1.0, 0.8)  # back on the desk
    assert where(r, "bag") is not None  # no longer gone
    assert where(r, "mug") is None  # only s2 saw it
    assert (done.things_forgotten, done.things_restored, done.furniture_removed) == (1, 2, 0)
    assert r.scans.get("s2") is None and not any(k.startswith(folder) for k in blobs.data)
    assert any(k.startswith(r.scans.get("s1").folder) for k in blobs.data)  # the other scan's photos stay
    action, detail = audit.events[-1]
    assert action == Action.SCAN_ERASED and detail["things_forgotten"] == 1
    assert len(r.homes.get("flat").landmarks) == 2


def test_erasing_a_rooms_only_scan_forgets_its_things_and_furniture():
    r, blobs, _, erase = two_scans()
    erase("s2")
    erase("s1")
    home = r.homes.get("flat")
    assert r.objects.list_for_home("flat") == [] and home.landmarks == []
    assert home.room_model is None and home.first_scan_id is None and blobs.data == {}


def test_a_scan_being_processed_or_unknown_is_not_erased():
    r, _, _, erase = two_scans()
    r.scan("s3", 14)  # still processing
    with pytest.raises(EraseError) as e:
        erase("s3")
    assert e.value.status == 409
    with pytest.raises(EraseError) as e:
        erase("nope")
    assert e.value.status == 404


def test_erasing_an_unrecognised_rescan_brings_the_earlier_memory_back():
    r = Repos()
    r.scan("s1", 10)
    r.ingest("s1", {"room": ROOM, "landmarks": [DESK], "objects": [obj("keys", [1.0, 1.0, 0.8])]})
    r.scan("s2", 12)  # not recognised: the room starts over
    r.ingest("s2", {"room": ROOM, "landmarks": [DESK], "objects": [obj("keys", [2.0, 2.0, 0.8])]})
    EraseScan(r.scans, r.homes, r.objects, MemoryBlobs())("s2")
    assert where(r, "keys") == (1.0, 1.0, 0.8)


def test_over_http_on_the_real_store_owner_only(tmp_path):
    import json

    from recall_api.infra.app import create_app
    from recall_api.infra.demo import SAMPLE, build, demo_settings

    if not (SAMPLE / "meta.json").exists():
        pytest.skip("no recorded sample")
    settings = demo_settings(tmp_path, RECALL_ROBOT_KEY="robot")
    c = build(settings, SAMPLE)
    scan_id = json.loads((SAMPLE / "meta.json").read_text())["scan_id"]
    scan: Scan = c.scans.get(scan_id)
    c.blobs.put(f"{scan.folder}/episode/frames/000001.jpg", b"photo")
    (settings.log_dir).mkdir(parents=True, exist_ok=True)
    log = settings.log_dir / f"{scan.folder.removeprefix('scans/')}.log"
    log.write_text("pipeline log")
    assert c.objects.list_for_home("flat")
    http = TestClient(create_app(settings))
    assert http.delete(f"/scans/{scan_id}", headers={"Authorization": "Bearer robot"}).status_code == 401
    assert http.delete(f"/scans/{scan_id}", headers={"Authorization": "Bearer demo"}).status_code == 204
    assert not (settings.data_dir / "blobs" / scan.folder).exists() and not log.exists()
    assert c.objects.list_for_home("flat") == [] and c.scans.get(scan_id) is None
    assert http.delete(f"/scans/{scan_id}", headers={"Authorization": "Bearer demo"}).status_code == 404
    events = http.get("/audit", headers={"Authorization": "Bearer demo"}).json()
    assert any(e["action"] == "scan.erased" for e in events)
