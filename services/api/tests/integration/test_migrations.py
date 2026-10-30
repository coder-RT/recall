from sqlalchemy import text

from recall_api.infra.db import make_engine, migrate


def test_migrations_apply_and_last_seen_returns_the_newest_confident_sighting(tmp_path):
    url = f"sqlite:///{tmp_path / 'recall.db'}"
    migrate(url)
    e = make_engine(url)
    with e.begin() as c:
        c.execute(text("INSERT INTO homes (id, name) VALUES ('flat', 'Flat')"))
        c.execute(
            text("""INSERT INTO scans (id, home_id, room, created_at, status, archive_size, archive_sha256, part_size)
                          VALUES ('s1', 'flat', 'Living room', '2026-10-30T10:00:00Z', 'processed', 1, 'x', 5242880)""")
        )
        c.execute(text("INSERT INTO objects (id, home_id, label) VALUES ('o1', 'flat', 'keys')"))
        rows = [
            ("a", "2026-10-30T10:00:00Z", 0.9, 0),
            ("b", "2026-10-30T11:00:00Z", 0.4, 0),
            ("c", "2026-10-30T10:30:00Z", 0.8, 0),
            ("d", "2026-10-30T12:00:00Z", 0.9, 1),
        ]
        for oid, ts, conf, stale in rows:
            c.execute(
                text("""INSERT INTO observations (id, object_id, scan_id, ts, x, y, z, confidence, stale)
                              VALUES (:id, 'o1', 's1', :ts, 0, 0, 0, :conf, :stale)"""),
                {"id": oid, "ts": ts, "conf": conf, "stale": stale},
            )
        got = c.execute(text("SELECT id FROM last_seen WHERE object_id = 'o1'")).scalars().all()
    assert got == ["c"]  # b is not confident, d is stale
