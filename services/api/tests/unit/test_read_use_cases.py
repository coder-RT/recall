"""The small use cases behind the routers: a scan's state, a failed scan, the room model, and a sighting's crop."""

import io
from datetime import UTC, datetime

from PIL import Image

from recall_api.adapters.outbound.vision.pillow_crop import PillowCropper
from recall_api.application.explain_answer import widen
from recall_api.application.get_room import GetRoom
from recall_api.application.get_scan import GetScan
from recall_api.application.mark_scan_failed import MarkScanFailed
from recall_api.domain.audit import Action, Outcome
from recall_api.domain.memory import Home, Scan, ScanStatus
from tests.fakes import MemoryRepo

AT = datetime(2026, 11, 1, 19, 0, tzinfo=UTC)


class Worker:
    def __init__(self, alive: bool) -> None:
        self.is_alive = alive

    def alive(self) -> bool:
        return self.is_alive


def _scan(status: ScanStatus) -> Scan:
    return Scan("s1", "flat", "Living room", status, 1, "x", 5242880, AT)


def test_the_worker_is_only_asked_about_while_processing():
    scans = MemoryRepo()
    scans.save(_scan(ScanStatus.PROCESSING))
    assert GetScan(scans, Worker(False))("s1").worker_alive is False
    scans.save(_scan(ScanStatus.PROCESSED))
    assert GetScan(scans, Worker(False))("s1").worker_alive is None
    assert GetScan(scans, Worker(True))("nope") is None


def test_a_failed_scan_says_why_and_is_audited():
    scans, events = MemoryRepo(), []
    scans.save(_scan(ScanStatus.PROCESSING))
    mark = MarkScanFailed(scans, audit=lambda *a, **k: events.append((a, k)))
    assert mark("s1", 139, "scan-s1")
    s = scans.get("s1")
    assert s.status == ScanStatus.FAILED and "exit 139" in s.detail and "scan-s1.log" in s.detail
    (action, _, outcome), detail = events[0]
    assert action == Action.SCAN_FAILED and outcome == Outcome.FAILED and detail["exit"] == 139
    assert not mark("gone", 1, "x")


def test_the_room_is_none_until_a_scan_is_processed():
    homes = MemoryRepo()
    homes.save(Home(id="flat", name="flat"))
    assert GetRoom(homes)("flat") is None
    assert GetRoom(homes)("nope") is None


def test_the_crop_keeps_a_margin_and_stays_inside_the_picture():
    assert widen((10, 10, 50, 30)) == (0.0, 5.0, 60.0, 35.0)  # 25 % of 40 x 20; the left edge stops at 0
    buf = io.BytesIO()
    Image.new("RGB", (64, 48), "white").save(buf, "JPEG")
    out = Image.open(io.BytesIO(PillowCropper().crop(buf.getvalue(), (0, 5, 100, 35))))
    assert out.size == (64, 30) and out.format == "JPEG"
