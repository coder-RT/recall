"""Alembic environment: plain SQL revisions against the SQLite memory store."""

from alembic import context
from recall_api.config.settings import Settings
from recall_api.infra.db import make_engine

# tests pass a temp database; otherwise the same database the API uses (data/recall.db at the repo root)
url = context.config.attributes.get("url") or Settings.load().db_url


def run() -> None:
    engine = make_engine(url)  # creates the data folder if needed
    with engine.connect() as conn:
        context.configure(connection=conn, target_metadata=None)
        with context.begin_transaction():
            context.run_migrations()


run()
