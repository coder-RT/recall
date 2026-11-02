"""The disk store and the SQLite repositories the erase relies on (real SQLite and a temp folder, no network)."""

from datetime import UTC, datetime

import pytest
from sqlalchemy import text

from recall_api.adapters.outbound.storage.local_disk import LocalDiskBlobStore
from recall_api.config.settings import Settings
from recall_api.domain.memory import Home, Observation, Position, Scan, ScanStatus, TrackedObject
from recall_api.infra.container import Container

AT = datetime(2026, 10, 30, 10, tzinfo=UTC)


def test_delete_prefix_removes_one_scan_folder_and_nothing_else(tmp_path):
    store = LocalDiskBlobStore(tmp_path)
    store.put("scans/a/episode/frames/1.jpg", b"x")
    store.put("scans/a/archive.zip", b"x")
    store.put("scans/b/archive.zip", b"x")
    store.delete_prefix("scans/a")
    assert not (tmp_path / "scans" / "a").exists() and store.exists("scans/b/archive.zip")
    store.delete_prefix("scans/missing")  # nothing there: no error


@pytest.mark.parametrize("key", ["", ".", "scans/..", "../outside"])
def test_delete_prefix_refuses_the_whole_store_or_anything_outside_it(tmp_path, key):
    (tmp_path / "store").mkdir()
    store = LocalDiskBlobStore(tmp_path / "store")
    store.put("scans/a/x", b"x")
    with pytest.raises(ValueError):
        store.delete_prefix(key)
    assert store.exists("scans/a/x")


def _container(tmp_path) -> Container:
    c = Container(Settings(RECALL_DATA_DIR=tmp_path, RECALL_TRACES="off"))
    c.homes.save(Home("flat", "flat"))
    for sid in ("s1", "s2"):
        c.scans.save(Scan(sid, "flat", "Office", ScanStatus.PROCESSED, 1, "x", 1, AT))
    return c


def test_saving_an_object_drops_the_sightings_it_no_longer_holds(tmp_path):
    c = _container(tmp_path)
    ob = lambda i, s: Observation(i, "o1", s, AT, Position(1, 1, 0.8), 0.9)  # noqa: E731
    obj = TrackedObject("o1", "flat", "keys", observations=[ob("a", "s1"), ob("b", "s2")])
    c.objects.save(obj)
    obj.observations = [ob("a", "s1")]
    c.objects.save(obj)
    assert [o.id for o in c.objects.get("o1").observations] == ["a"]
    obj.observations = []
    c.objects.save(obj)
    assert c.objects.get("o1").observations == []


def test_deleting_a_scan_removes_its_keyframes(tmp_path):
    c = _container(tmp_path)
    with c.engine.begin() as db:
        db.execute(text("INSERT INTO keyframes (id, scan_id, idx, ts, image_uri, pose_4x4, tracking_state) "
                        "VALUES ('k1', 's1', 0, 0.5, 'x', '[]', 'normal')"))  # fmt: skip
    c.scans.delete("s1")
    assert c.scans.get("s1") is None and c.scans.get("s2") is not None
    with c.engine.connect() as db:
        assert db.execute(text("SELECT count(*) FROM keyframes")).scalar() == 0


def test_many_first_requests_at_once_open_the_database_once(tmp_path):
    # the phone sends several requests together when the app opens; Alembic must not run twice at once
    from concurrent.futures import ThreadPoolExecutor

    from recall_api.config.settings import Settings
    from recall_api.infra.container import Container

    c = Container(Settings(RECALL_DATA_DIR=tmp_path, RECALL_TRACES="off"))
    with ThreadPoolExecutor(8) as pool:
        engines = list(pool.map(lambda _: c.engine, range(16)))
    assert len({id(e) for e in engines}) == 1
