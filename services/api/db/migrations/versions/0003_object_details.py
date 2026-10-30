"""Object details: colour and size from the scan; the user's corrections after a scan.

Revision ID: 0003
"""

from alembic import op

revision = "0003"
down_revision = "0002"

COLUMNS = (
    "color TEXT",
    "size_m TEXT",  # JSON [x, y, z]
    "user_name TEXT",
    "user_color TEXT",
    "user_height_m REAL",
    "user_note TEXT",
    "confirmed INTEGER NOT NULL DEFAULT 0",
)


def upgrade() -> None:
    for col in COLUMNS:
        op.execute(f"ALTER TABLE objects ADD COLUMN {col}")


def downgrade() -> None:
    for col in reversed(COLUMNS):
        op.execute(f"ALTER TABLE objects DROP COLUMN {col.split()[0]}")
