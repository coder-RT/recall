"""A scan waiting in the queue with no worker running says so, instead of "processing" forever."""

from datetime import UTC, datetime, timedelta

from fastapi.testclient import TestClient

from recall_api.adapters.outbound.jobs.heartbeat import FileHeartbeat
from recall_api.config.settings import Settings
from recall_api.domain.memory import Home, Scan, ScanStatus
from recall_api.infra.app import create_app


class Clock:
    def __init__(self) -> None:
        self.at = datetime(2026, 11, 1, 19, 0, tzinfo=UTC)

    def now(self):
        return self.at


def test_the_worker_is_alive_while_it_beats_and_not_after(tmp_path):
    clock = Clock()
    hb = FileHeartbeat(tmp_path / "worker-heartbeat", clock)
    assert not hb.alive()  # never started
    hb.beat()
    clock.at += timedelta(seconds=60)
    assert hb.alive()
    clock.at += timedelta(seconds=31)  # 91 s since the last beat: the worker stopped
    assert not hb.alive()
    (tmp_path / "worker-heartbeat").write_text("not a time")
    assert not hb.alive()


def test_a_processing_scan_says_whether_anyone_is_processing_it(tmp_path):
    s = Settings(
        RECALL_DATA_DIR=tmp_path, RECALL_DEVICE_KEY="owner", RECALL_PIPELINE_RUNNER="queue", RECALL_TRACES="off"
    )
    app = create_app(s)
    c = app.state.container
    c.homes.save(Home(id="flat", name="flat"))
    c.scans.save(Scan("0b9f2a1e-0000-4000-8000-000000000002", "flat", "Living room", ScanStatus.PROCESSING, 1, "x",
                      5242880, datetime.now(UTC)))  # fmt: skip
    client = TestClient(app)
    url, key = "/scans/0b9f2a1e-0000-4000-8000-000000000002", {"Authorization": "Bearer owner"}
    assert client.get(url, headers=key).json()["worker_alive"] is False  # no worker has ever beaten
    FileHeartbeat(tmp_path / "worker-heartbeat", c.clock).beat()
    assert client.get(url, headers=key).json()["worker_alive"] is True
