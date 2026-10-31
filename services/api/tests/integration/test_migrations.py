import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import text
from sqlalchemy.exc import DatabaseError

from recall_api.infra.db import API_ROOT, make_engine, migrate

SCAN = """INSERT INTO scans (id, home_id, room, created_at, status, archive_size, archive_sha256, part_size)
          VALUES ('s1', 'flat', 'Living room', '2026-10-30T10:00:00Z', 'processed', 1, 'x', 5242880)"""
ROWS = [("a", "2026-10-30T10:00:00Z", 0.9), ("b", "2026-10-30T11:00:00Z", 0.4), ("c", "2026-10-30T10:30:00Z", 0.8),
        ("d", "2026-10-30T12:00:00Z", 0.9)]  # fmt: skip


def _upgrade(url: str, to: str) -> None:
    cfg = Config(str(API_ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(API_ROOT / "db" / "migrations"))
    cfg.attributes["url"] = url
    command.upgrade(cfg, to)


def _sightings(c, stale_d: bool | None = None):
    c.execute(text("INSERT INTO homes (id, name) VALUES ('flat', 'Flat')"))
    c.execute(text(SCAN))
    c.execute(text("INSERT INTO objects (id, home_id, label) VALUES ('o1', 'flat', 'keys')"))
    for oid, ts, conf in ROWS:
        cols, vals = "", ""
        if stale_d is not None:
            cols, vals = ", stale", f", {int(stale_d and oid == 'd')}"
        sql = (f"INSERT INTO observations (id, object_id, scan_id, ts, x, y, z, confidence{cols}) "
               f"VALUES (:id, 'o1', 's1', :ts, 0, 0, 0, :conf{vals})")  # fmt: skip
        c.execute(text(sql), {"id": oid, "ts": ts, "conf": conf})


def test_last_seen_is_the_newest_confident_sighting_not_set_aside(tmp_path):
    url = f"sqlite:///{tmp_path / 'recall.db'}"
    migrate(url)
    e = make_engine(url)
    with e.begin() as c:
        _sightings(c)
        assert c.execute(text("SELECT id FROM last_seen")).scalars().all() == ["d"]
        c.execute(
            text("""INSERT INTO set_asides (id, object_id, scan_id, reason, at, observation_ids)
                          VALUES ('sa1', 'o1', 's2', 'moved', '2026-10-30T13:00:00Z', '["d"]')""")
        )
        assert c.execute(text("SELECT id FROM last_seen")).scalars().all() == ["c"]  # b is not confident, d set aside


def test_stale_flags_become_set_asides_on_upgrade(tmp_path):
    url = f"sqlite:///{tmp_path / 'recall.db'}"
    _upgrade(url, "0006")
    e = make_engine(url)
    with e.begin() as c:
        _sightings(c, stale_d=True)
    _upgrade(url, "head")
    with e.begin() as c:
        (row,) = c.execute(text("SELECT object_id, reason, observation_ids FROM set_asides")).all()
        assert row == ("o1", "migrated", '["d"]')
        assert c.execute(text("SELECT id FROM last_seen")).scalars().all() == ["c"]


def test_sightings_set_asides_and_answers_cannot_be_edited(tmp_path):
    url = f"sqlite:///{tmp_path / 'recall.db'}"
    migrate(url)
    e = make_engine(url)
    with e.begin() as c:
        _sightings(c)
    for sql in ("UPDATE observations SET x = 1 WHERE id = 'a'", "UPDATE set_asides SET reason = 'x'"):
        with pytest.raises(DatabaseError, match="append-only"), e.begin() as c:
            c.execute(
                text("""INSERT OR IGNORE INTO set_asides (id, object_id, scan_id, reason, at, observation_ids)
                              VALUES ('sa1', 'o1', NULL, 'gone', '2026-10-30T13:00:00Z', '[]')""")
            )
            c.execute(text(sql))
    with e.begin() as c:  # erasing (the privacy exception) can still delete
        c.execute(text("DELETE FROM observations WHERE id = 'a'"))
