"""How many photos showed each sighting (so a thing seen once can wait for the owner), and the things the owner said
aren't there, so later scans don't bring them back.

Revision ID: 0008
"""

from alembic import op

revision = "0008"
down_revision = "0007"


def upgrade() -> None:
    op.execute("ALTER TABLE observations ADD COLUMN photos INTEGER")
    op.execute("""
CREATE TABLE rejections (
  id TEXT PRIMARY KEY,
  home_id TEXT NOT NULL REFERENCES homes(id),
  label TEXT NOT NULL,
  x REAL NOT NULL,
  y REAL NOT NULL,
  z REAL NOT NULL,
  at TEXT NOT NULL
)""")
    op.execute("CREATE INDEX rejections_home ON rejections (home_id)")


def downgrade() -> None:
    op.execute("DROP TABLE rejections")
    op.execute("ALTER TABLE observations DROP COLUMN photos")
