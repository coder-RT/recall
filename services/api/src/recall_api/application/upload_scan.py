"""Resumable episode upload: plan, parts, manifest last, then verify and start the pipeline."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any

from recall_api.application.ports import BlobStore, Clock, EpisodeUnpacker, PipelineTrigger
from recall_api.domain.memory import Home, Scan, ScanStatus
from recall_api.domain.ports import HomeRepository, ScanRepository

MANIFEST_FORMAT = "recall-episode/1"


class UploadError(Exception):
    """Something the client can fix; `code` is machine-readable, the message is one plain sentence."""

    def __init__(self, code: str, message: str, status: int = 422) -> None:
        super().__init__(message)
        self.code = code
        self.status = status


def _keys(scan: Scan) -> dict[str, str]:
    base = scan.folder
    return {
        "base": base,
        "manifest": f"{base}/manifest.json",
        "archive": f"{base}/archive.zip",
        "episode": f"{base}/episode",
    }


def part_key(scan: Scan, number: int) -> str:
    return f"{scan.folder}/parts/{number:05d}"


@dataclass
class UploadPlan:
    scan: Scan
    received: set[int]


class UploadScan:
    def __init__(
        self,
        scans: ScanRepository,
        homes: HomeRepository,
        blobs: BlobStore,
        unpacker: EpisodeUnpacker,
        trigger: PipelineTrigger,
        clock: Clock,
    ) -> None:
        self.scans, self.homes, self.blobs, self.unpacker, self.trigger, self.clock = (
            scans,
            homes,
            blobs,
            unpacker,
            trigger,
            clock,
        )

    def create(self, scan_id: str, home_id: str, room: str, size: int, sha256: str, part_size: int) -> UploadPlan:
        scan = self.scans.get(scan_id)
        if scan is None:
            if self.homes.get(home_id) is None:
                self.homes.save(Home(id=home_id, name=home_id))
            scan = Scan(
                id=scan_id,
                home_id=home_id,
                room=room,
                status=ScanStatus.UPLOADING,
                archive_size=size,
                archive_sha256=sha256,
                part_size=part_size,
                created_at=self.clock.now(),
            )
            self.scans.save(scan)
            self.trigger.warm()  # the model loads while the parts upload
        elif (scan.archive_size, scan.archive_sha256, scan.part_size) != (size, sha256, part_size):
            raise UploadError("archive_changed", "This scan id was started with a different archive.", 409)
        return UploadPlan(scan, self._received(scan))

    def _received(self, scan: Scan) -> set[int]:
        return {
            n
            for n in range(1, scan.part_count + 1)
            if self.blobs.exists(part_key(scan, n)) and self.blobs.size(part_key(scan, n)) == scan.expected_part_size(n)
        }

    def _uploading(self, scan_id: str) -> Scan:
        scan = self.scans.get(scan_id)
        if scan is None:
            raise UploadError("not_found", "No such scan.", 404)
        if scan.status != ScanStatus.UPLOADING:
            raise UploadError("not_uploading", f"The scan is already {scan.status.value}.", 409)
        return scan

    def put_part(self, scan_id: str, number: int, data: bytes, sha256: str) -> int:
        scan = self._uploading(scan_id)
        try:
            expected = scan.expected_part_size(number)
        except ValueError as e:
            raise UploadError("bad_part_number", str(e)) from e
        if len(data) != expected:
            raise UploadError("bad_part_size", f"Part {number} should be {expected} bytes, got {len(data)}.")
        if hashlib.sha256(data).hexdigest() != sha256:
            raise UploadError("bad_part_checksum", f"Part {number} arrived damaged; send it again.")
        self.blobs.put(part_key(scan, number), data)
        return len(data)

    def put_manifest(self, scan_id: str, manifest: dict[str, Any]) -> Scan:
        scan = self._uploading(scan_id)
        if manifest.get("scan_id") != scan_id or manifest.get("format") != MANIFEST_FORMAT:
            raise UploadError("bad_manifest", "The manifest belongs to another scan or format.")
        missing = set(range(1, scan.part_count + 1)) - self._received(scan)
        if missing:
            raise UploadError(
                "parts_missing", f"Upload the manifest last; {len(missing)} parts are still missing.", 409
            )
        self.blobs.put(_keys(scan)["manifest"], json.dumps(manifest).encode())
        scan.frame_count = int(manifest.get("frame_count", 0))
        self.scans.save(scan)
        return scan

    def complete(self, scan_id: str) -> Scan:
        scan = self._uploading(scan_id)
        keys = _keys(scan)
        if not self.blobs.exists(keys["manifest"]):
            raise UploadError("manifest_missing", "Upload the manifest before completing.", 409)
        digest = hashlib.sha256()
        chunks: list[bytes] = []
        for n in range(1, scan.part_count + 1):
            part = self.blobs.get(part_key(scan, n))
            digest.update(part)
            chunks.append(part)
        if digest.hexdigest() != scan.archive_sha256:
            scan.status, scan.detail = ScanStatus.FAILED, "The uploaded archive does not match its checksum."
            self.scans.save(scan)
            return scan
        self.blobs.put(keys["archive"], b"".join(chunks))
        files = {f.path: f for f in self.unpacker.unpack(keys["archive"], keys["episode"])}
        manifest = json.loads(self.blobs.get(keys["manifest"]))
        for entry in manifest["files"]:
            got = files.get(entry["path"])
            if got is None or got.sha256 != entry["sha256"] or got.size != entry["size"]:
                scan.status, scan.detail = ScanStatus.FAILED, f"{entry['path']} is missing or damaged in the archive."
                self.scans.save(scan)
                return scan
        scan.status, scan.detail = ScanStatus.UPLOADED, None
        scan.aligned_to = manifest.get("aligned_to")  # a rescan the phone recognised in an earlier scan's map
        self.scans.save(scan)
        episode_dir = self.blobs.local_path(keys["episode"]) or keys["episode"]
        self.trigger.start(scan.folder.removeprefix("scans/"), scan_id, episode_dir)
        scan.status = ScanStatus.PROCESSING
        self.scans.save(scan)
        return scan
