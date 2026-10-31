"""Engine and migrations. The schema is plain SQL in db/migrations."""

from __future__ import annotations

from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import Engine, create_engine, event

API_ROOT = Path(__file__).resolve().parents[3]


def make_engine(url: str) -> Engine:
    if url.startswith("sqlite:///"):
        Path(url.removeprefix("sqlite:///")).parent.mkdir(parents=True, exist_ok=True)
    engine = create_engine(url)

    @event.listens_for(engine, "connect")
    def _fk(conn, _):  # SQLite: enforce foreign keys, wait instead of failing when the pipeline writes concurrently
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA busy_timeout = 5000")

    return engine


def migrate(url: str) -> None:
    cfg = Config(str(API_ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(API_ROOT / "db" / "migrations"))
    cfg.attributes["url"] = url
    command.upgrade(cfg, "head")
