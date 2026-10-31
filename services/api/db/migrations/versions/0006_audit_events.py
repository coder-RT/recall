"""The audit log: append-only events (who, what, outcome), kept for the retention period.

Revision ID: 0006
"""

from alembic import op

revision = "0006"
down_revision = "0005"


def upgrade() -> None:
    op.execute("""
CREATE TABLE audit_events (
  id TEXT PRIMARY KEY,
  at TEXT NOT NULL,
  actor TEXT NOT NULL,
  action TEXT NOT NULL,
  outcome TEXT NOT NULL,
  target_type TEXT,
  target_id TEXT,
  detail TEXT NOT NULL DEFAULT '{}',
  request_id TEXT
)""")
    op.execute("CREATE INDEX audit_events_at ON audit_events (at)")
    op.execute("CREATE INDEX audit_events_action_at ON audit_events (action, at)")
    # append-only in the database too: no UPDATE of a recorded event
    op.execute("""
CREATE TRIGGER audit_events_no_update BEFORE UPDATE ON audit_events
BEGIN SELECT RAISE(ABORT, 'audit events are append-only'); END""")


def downgrade() -> None:
    op.execute("DROP TRIGGER audit_events_no_update")
    op.execute("DROP TABLE audit_events")
