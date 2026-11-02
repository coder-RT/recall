"""A scan the pipeline gave up on: marked failed with the reason the phone shows, and audited. The queue worker's
last retry calls this, so the API stays the only writer of the memory."""

from __future__ import annotations

from recall_api.application.audit import NoAudit
from recall_api.domain.audit import Action, Actor, Outcome
from recall_api.domain.memory import ScanStatus
from recall_api.domain.ports import ScanRepository


class MarkScanFailed:
    def __init__(self, scans: ScanRepository, audit=None) -> None:
        self.scans = scans
        self.audit = audit or NoAudit()

    def __call__(self, scan_id: str, exit_code: int, log_name: str) -> bool:
        scan = self.scans.get(scan_id)
        if scan is None:
            return False
        scan.status = ScanStatus.FAILED
        scan.detail = f"Processing failed (exit {exit_code}). The Mac's log is data/logs/{log_name}.log."
        self.scans.save(scan)
        self.audit(Action.SCAN_FAILED, Actor.PIPELINE, Outcome.FAILED, target_type="scan", target_id=scan_id,
                   room=scan.room, exit=exit_code)  # fmt: skip
        return True
