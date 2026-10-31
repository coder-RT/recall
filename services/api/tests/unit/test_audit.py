"""The audit log: an append-only record of who did what, by the key they used, never a secret."""

from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from recall_api.adapters.outbound.persistence.sqlite import SqliteAuditLog
from recall_api.application.ports import Screening
from recall_api.config.settings import Settings
from recall_api.domain.audit import Action, Actor, AuditEvent, Outcome, clean
from recall_api.infra.app import create_app
from recall_api.infra.db import make_engine, migrate
from tests.unit.test_home_memory import agent
from tests.unit.test_robot_export import _exporter

OWNER = {"Authorization": "Bearer owner"}
ROBOT = {"Authorization": "Bearer robot"}


def test_clean_drops_secrets_and_trims_text():
    out = clean({"api_key": "sk-1", "Authorization": "Bearer x", "token": "t", "asked": "a" * 400, "n": 3,
                 "fields": ["name", 1, {"x": 1}], "nested": {"password": "p", "ok": True}})  # fmt: skip
    assert "api_key" not in out and "Authorization" not in out and "token" not in out
    assert len(out["asked"]) == 160 and out["asked"].endswith("…")
    assert out["fields"] == ["name", 1] and out["nested"] == {"ok": True} and out["n"] == 3


@pytest.fixture
def store(tmp_path):
    url = f"sqlite:///{tmp_path}/a.db"
    migrate(url)
    return SqliteAuditLog(make_engine(url)), make_engine(url)


def ev(i, at, action=Action.HOME_MEMORY_QUERY, actor=Actor.ROBOT):
    return AuditEvent(f"ev{i}", at, actor, action, Outcome.OK, detail={"i": i})


def test_store_reads_newest_first_filters_and_prunes(store):
    log, _ = store
    t0 = datetime(2026, 10, 31, 12, tzinfo=UTC)
    for i in range(5):
        log.record(ev(i, t0 + timedelta(minutes=i), Action.ROBOT_EXPORT_READ if i % 2 else Action.HOME_MEMORY_QUERY))
    assert [e.id for e in log.recent(3)] == ["ev4", "ev3", "ev2"]
    assert {e.action for e in log.recent(action="robot_export.read")} == {Action.ROBOT_EXPORT_READ}
    assert [e.id for e in log.recent(since=t0 + timedelta(minutes=3))] == ["ev4", "ev3"]
    assert log.recent(1)[0].detail == {"i": 4}
    assert log.prune(t0 + timedelta(minutes=2)) == 2 and len(log.recent(50)) == 3


def test_recorded_events_cannot_be_edited(store):
    log, engine = store
    log.record(ev(1, datetime(2026, 10, 31, tzinfo=UTC)))
    with pytest.raises(Exception, match="append-only"), engine.begin() as c:
        c.execute(text("UPDATE audit_events SET outcome = 'ok' WHERE id = 'ev1'"))


def _client(tmp_path):
    s = Settings(RECALL_DATA_DIR=tmp_path, RECALL_DEVICE_KEY="owner", RECALL_ROBOT_KEY="robot",
                 RECALL_PUBLIC_URL="http://testserver", RECALL_TRACES="off")  # fmt: skip
    app = create_app(s)
    c = app.state.container
    c.__dict__["export_for_robot"] = _exporter(tmp_path)[0]
    ask, _ = agent(Screening(True, "ok", by="muse-spark-open"))
    ask.audit = c.auditor
    c.__dict__["answer_external_query"] = ask
    return TestClient(app), c


def test_the_actions_that_matter_are_recorded_by_who_did_them(tmp_path):
    client, c = _client(tmp_path)
    client.get("/homes/flat/robot-export", headers=ROBOT)  # refused: access off
    client.put("/sharing", json={"robot_access": True}, headers=OWNER)
    client.get("/homes/flat/robot-export", headers=ROBOT)
    client.get("/homes/flat/robot-export", headers={"Authorization": "Bearer guess-1234"})
    c.answer_external_query("flat", {"object": "keys"})
    events = client.get("/audit", headers=OWNER).json()
    got = [(e["action"], e["actor"], e["outcome"]) for e in reversed(events)]
    assert got == [
        ("robot_export.read", "robot", "refused"),
        ("robot_access.changed", "owner", "ok"),
        ("robot_export.read", "robot", "ok"),
        ("auth.refused", "unknown", "refused"),
        ("home_memory.query", "robot", "ok"),
    ]
    query = events[0]
    assert query["detail"]["screened_by"] == "muse-spark-open" and query["detail"]["asked"] == "keys"
    assert query["detail"]["found"] is True and query["target_type"] == "object"
    assert all(e["request_id"] for e in events[1:])  # the HTTP ones carry the request id
    assert "guess-1234" not in str(events)  # a wrong key is never stored
    assert events[2]["detail"]["things"] == 1 and events[3]["detail"] == {"on": True, "was": False}


def test_only_the_owner_reads_the_log(tmp_path):
    client, _ = _client(tmp_path)
    assert client.get("/audit", headers=ROBOT).status_code == 401
    assert client.get("/audit").status_code == 401
    assert client.get("/audit?actor=unknown", headers=OWNER).json()[0]["action"] == "auth.refused"  # both tries
