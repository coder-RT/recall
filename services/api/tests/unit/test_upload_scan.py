import hashlib
import os

import pytest

from recall_api.application.upload_scan import UploadError, UploadScan
from recall_api.domain.memory import ScanStatus
from tests.fakes import FixedClock, MemoryBlobs, MemoryRepo, MemoryUnpacker, RecordingTrigger, episode_zip

SCAN = "0b9f2a1e-0000-4000-8000-000000000001"
PART = 5 * 1024 * 1024


def setup(files=None):
    blobs = MemoryBlobs()
    trigger = RecordingTrigger()
    up = UploadScan(MemoryRepo(), MemoryRepo(), blobs, MemoryUnpacker(blobs), trigger, FixedClock())
    # an incompressible frame bigger than one part, so the archive needs two parts
    files = files or {"frames/000000.jpg": os.urandom(PART + 10), "poses.jsonl": b"{}\n" * 10}
    archive = episode_zip(files)
    manifest = {
        "scan_id": SCAN,
        "format": "recall-episode/1",
        "frame_count": 1,
        "files": [{"path": p, "size": len(d), "sha256": hashlib.sha256(d).hexdigest()} for p, d in files.items()],
    }
    return up, trigger, archive, manifest


def parts(archive):
    return [archive[i : i + PART] for i in range(0, len(archive), PART)]


def test_a_full_upload_verifies_and_starts_the_pipeline():
    up, trigger, archive, manifest = setup()
    plan = up.create(SCAN, "flat", "Living room", len(archive), hashlib.sha256(archive).hexdigest(), PART)
    assert plan.scan.part_count == 2 and plan.received == set()
    for n, p in enumerate(parts(archive), 1):
        up.put_part(SCAN, n, p, hashlib.sha256(p).hexdigest())
    up.put_manifest(SCAN, manifest)
    scan = up.complete(SCAN)
    assert scan.status == ScanStatus.PROCESSING and trigger.started == [(SCAN, f"scans/{SCAN}/episode")]


def test_resuming_reports_the_parts_already_received():
    up, _, archive, _ = setup()
    sha = hashlib.sha256(archive).hexdigest()
    up.create(SCAN, "flat", "Living room", len(archive), sha, PART)
    first = parts(archive)[0]
    up.put_part(SCAN, 1, first, hashlib.sha256(first).hexdigest())
    assert up.create(SCAN, "flat", "Living room", len(archive), sha, PART).received == {1}


def test_a_damaged_part_is_refused():
    up, _, archive, _ = setup()
    up.create(SCAN, "flat", "Living room", len(archive), hashlib.sha256(archive).hexdigest(), PART)
    with pytest.raises(UploadError) as e:
        up.put_part(SCAN, 1, parts(archive)[0], "0" * 64)
    assert e.value.code == "bad_part_checksum"


def test_the_manifest_must_come_last():
    up, _, archive, manifest = setup()
    up.create(SCAN, "flat", "Living room", len(archive), hashlib.sha256(archive).hexdigest(), PART)
    with pytest.raises(UploadError) as e:
        up.put_manifest(SCAN, manifest)
    assert e.value.code == "parts_missing"


def test_a_file_that_does_not_match_the_manifest_fails_the_scan():
    up, trigger, archive, manifest = setup()
    manifest["files"][0]["sha256"] = "f" * 64
    up.create(SCAN, "flat", "Living room", len(archive), hashlib.sha256(archive).hexdigest(), PART)
    for n, p in enumerate(parts(archive), 1):
        up.put_part(SCAN, n, p, hashlib.sha256(p).hexdigest())
    up.put_manifest(SCAN, manifest)
    scan = up.complete(SCAN)
    assert scan.status == ScanStatus.FAILED and "frames/000000.jpg" in scan.detail and trigger.started == []
