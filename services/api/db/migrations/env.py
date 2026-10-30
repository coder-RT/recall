"""Alembic environment: plain SQL revisions against the SQLite memory store."""

import os

from alembic import context
from sqlalchemy import create_engine

url = context.config.attributes.get("url") or os.environ.get("RECALL_DATABASE_URL", "sqlite:///data/recall.db")


def run() -> None:
    engine = create_engine(url)
    with engine.connect() as conn:
        context.configure(connection=conn, target_metadata=None)
        with context.begin_transaction():
            context.run_migrations()


run()
