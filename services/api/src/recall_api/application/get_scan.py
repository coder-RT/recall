"""One scan's state for the phone, and whether anyone is processing it (a stopped worker is said, not hidden)."""

from __future__ import annotations

from dataclasses import dataclass

from recall_api.application.ports import WorkerStatus
from recall_api.domain.memory import Scan, ScanStatus
from recall_api.domain.ports import ScanRepository


@dataclass(frozen=True)
class ScanState:
    scan: Scan
    worker_alive: bool | None  # only while processing: None otherwise


class GetScan:
    def __init__(self, scans: ScanRepository, worker: WorkerStatus) -> None:
        self.scans, self.worker = scans, worker

    def __call__(self, scan_id: str) -> ScanState | None:
        scan = self.scans.get(scan_id)
        if scan is None:
            return None
        alive = self.worker.alive() if scan.status == ScanStatus.PROCESSING else None
        return ScanState(scan, alive)
