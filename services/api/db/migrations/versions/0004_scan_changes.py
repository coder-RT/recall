"""Rescans: the earlier scan a rescan was aligned to, whether memory started fresh, and what changed.

Revision ID: 0004
"""

from alembic import op

revision = "0004"
down_revision = "0003"

COLUMNS = (
    "aligned_to TEXT",
    "fresh INTEGER NOT NULL DEFAULT 0",
    "changes TEXT",  # JSON list of {kind, object_id, label, name, color, from, to}
)


def upgrade() -> None:
    for col in COLUMNS:
        op.execute(f"ALTER TABLE scans ADD COLUMN {col}")


def downgrade() -> None:
    for col in reversed(COLUMNS):
        op.execute(f"ALTER TABLE scans DROP COLUMN {col.split()[0]}")
