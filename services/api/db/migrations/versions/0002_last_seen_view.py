"""View last_seen: the newest non-stale observation per object with confidence >= 0.5.

Revision ID: 0002
"""

from alembic import op

revision = "0002"
down_revision = "0001"


def upgrade() -> None:
    op.execute("""
CREATE VIEW last_seen AS
SELECT o.* FROM observations o
WHERE o.stale = 0 AND o.confidence >= 0.5
  AND o.ts = (SELECT MAX(o2.ts) FROM observations o2
              WHERE o2.object_id = o.object_id AND o2.stale = 0 AND o2.confidence >= 0.5)
""")


def downgrade() -> None:
    op.execute("DROP VIEW last_seen")
