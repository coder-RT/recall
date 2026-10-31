"""Sightings become an append-only log: "set aside" records replace the stale flag, sightings keep their box, scans
their provenance, and every answer is logged with the tool results and sightings behind it.

Revision ID: 0007
"""

from alembic import op

revision = "0007"
down_revision = "0006"


def upgrade() -> None:
    op.execute("ALTER TABLE observations ADD COLUMN box TEXT")
    op.execute("ALTER TABLE scans ADD COLUMN provenance TEXT")
    op.execute("""
CREATE TABLE set_asides (
  id TEXT PRIMARY KEY,
  object_id TEXT NOT NULL REFERENCES objects(id),
  scan_id TEXT,
  reason TEXT NOT NULL,
  at TEXT NOT NULL,
  observation_ids TEXT NOT NULL
)""")
    op.execute("CREATE INDEX set_asides_object ON set_asides (object_id)")
    # today's stale flags become one migrated set-aside per object, then the flag is no longer used
    op.execute("""
INSERT INTO set_asides (id, object_id, scan_id, reason, at, observation_ids)
SELECT 'sa_migrated_' || object_id, object_id, NULL, 'migrated', MAX(ts), json_group_array(id)
FROM observations WHERE stale = 1 GROUP BY object_id""")
    op.execute("UPDATE observations SET stale = 0")
    # append-only in the database too; deleting is allowed only because erasing a scan is the privacy exception
    op.execute("""
CREATE TRIGGER observations_no_update BEFORE UPDATE ON observations
BEGIN SELECT RAISE(ABORT, 'sightings are append-only'); END""")
    op.execute("""
CREATE TRIGGER set_asides_no_update BEFORE UPDATE ON set_asides
BEGIN SELECT RAISE(ABORT, 'set-asides are append-only'); END""")
    op.execute("DROP VIEW last_seen")
    op.execute("""
CREATE VIEW last_seen AS
SELECT o.* FROM observations o
WHERE o.confidence >= 0.5
  AND NOT EXISTS (SELECT 1 FROM set_asides s, json_each(s.observation_ids) j WHERE j.value = o.id)
  AND o.ts = (SELECT MAX(o2.ts) FROM observations o2
              WHERE o2.object_id = o.object_id AND o2.confidence >= 0.5
                AND NOT EXISTS (SELECT 1 FROM set_asides s2, json_each(s2.observation_ids) j2 WHERE j2.value = o2.id))
""")
    op.execute("""
CREATE TABLE answer_log (
  id TEXT PRIMARY KEY,
  home_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  question TEXT NOT NULL,
  text TEXT NOT NULL,
  grounded INTEGER NOT NULL,
  object_id TEXT,
  steps TEXT NOT NULL,
  observation_ids TEXT NOT NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  prompt_tokens INTEGER,
  completion_tokens INTEGER,
  latency_ms INTEGER NOT NULL
)""")
    op.execute("CREATE INDEX answer_log_home_at ON answer_log (home_id, created_at)")
    op.execute("""
CREATE TRIGGER answer_log_no_update BEFORE UPDATE ON answer_log
BEGIN SELECT RAISE(ABORT, 'the answer log is append-only'); END""")


def downgrade() -> None:
    op.execute("DROP TRIGGER answer_log_no_update")
    op.execute("DROP TABLE answer_log")
    op.execute("DROP VIEW last_seen")
    op.execute("DROP TRIGGER set_asides_no_update")
    op.execute("DROP TRIGGER observations_no_update")
    op.execute("""
UPDATE observations SET stale = 1
WHERE id IN (SELECT j.value FROM set_asides s, json_each(s.observation_ids) j)""")
    op.execute("DROP TABLE set_asides")
    op.execute("""
CREATE VIEW last_seen AS
SELECT o.* FROM observations o
WHERE o.stale = 0 AND o.confidence >= 0.5
  AND o.ts = (SELECT MAX(o2.ts) FROM observations o2
              WHERE o2.object_id = o.object_id AND o2.stale = 0 AND o2.confidence >= 0.5)
""")
