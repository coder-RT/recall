"""Owner settings changed from the phone (robot access: off by default).

Revision ID: 0005
"""

from alembic import op

revision = "0005"
down_revision = "0004"


def upgrade() -> None:
    op.execute("CREATE TABLE owner_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")


def downgrade() -> None:
    op.execute("DROP TABLE owner_settings")
