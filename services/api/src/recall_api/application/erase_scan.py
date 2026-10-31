"""Erase one scan from the Mac: its photos, depth and files, and what memory learnt from it.

Memory goes back to what the room's other scans say. Erasing the room's newest scan restores exactly what it changed
(things it marked moved or gone are where the earlier scan saw them; the earlier room shape is back). Erasing an older
scan keeps the newer scans' view of the room. A thing seen only in this scan is forgotten; a room with no scans left
loses its furniture too.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from dataclasses import dataclass

from recall_api.application.audit import NoAudit
from recall_api.application.ports import BlobStore
from recall_api.domain.audit import Action, Actor
from recall_api.domain.memory import RoomModel, Scan, ScanStatus
from recall_api.domain.ports import HomeRepository, ScanRepository, TrackedObjectRepository


class EraseError(Exception):
    def __init__(self, code: str, message: str, status: int) -> None:
        super().__init__(message)
        self.code, self.message, self.status = code, message, status


@dataclass(frozen=True)
class Erased:
    scan_id: str
    things_forgotten: int
    things_restored: int
    furniture_removed: int


class EraseScan:
    def __init__(
        self, scans: ScanRepository, homes: HomeRepository, objects: TrackedObjectRepository, blobs: BlobStore,
        remove_files: Callable[[str], None] = lambda folder: None, audit=None,
    ) -> None:  # fmt: skip
        self.scans, self.homes, self.objects, self.blobs = scans, homes, objects, blobs
        self.remove_files = remove_files  # the scan's log and regression copy, outside the blob store
        self.audit = audit or NoAudit()

    def __call__(self, scan_id: str, actor: Actor = Actor.OWNER) -> Erased:
        scan = self.scans.get(scan_id)
        if scan is None:
            raise EraseError("not_found", "No such scan.", 404)
        if scan.status in (ScanStatus.UPLOADED, ScanStatus.PROCESSING):
            raise EraseError("busy", "The Mac is processing this scan; erase it when it has finished.", 409)
        others = [
            s for s in self.scans.list_for_home(scan.home_id) if s.id != scan.id and s.status == ScanStatus.PROCESSED
        ]
        same_room = [s for s in others if s.room == scan.room]
        newest_of_room = not any(s.created_at > scan.created_at for s in same_room)
        rooms = {s.id: s.room for s in others}
        restore = {c.object_id for c in scan.changes if c.kind in ("moved", "gone")} if newest_of_room else set()

        forgotten = restored = 0
        for obj in self.objects.list_for_home(scan.home_id):
            kept = [o for o in obj.observations if o.scan_id != scan.id]
            touched = len(kept) != len(obj.observations)
            if touched and not kept:
                self.objects.delete(obj.id)
                forgotten += 1
                continue
            # an unrecognised rescan set the room's earlier memory aside; the room's earlier scans speak again
            reset = scan.fresh and newest_of_room and kept and rooms.get(kept[-1].scan_id) == scan.room
            if obj.id in restore or reset:
                newest = max(kept, key=lambda o: o.seen_at)
                if newest.stale:
                    newest.stale = False
                    restored += 1
                    touched = True
            if touched:
                obj.observations = kept
                self.objects.save(obj)

        home = self.homes.get(scan.home_id)
        furniture = 0
        if home is not None:
            if not same_room:
                furniture = sum(1 for lm in home.landmarks if lm.room == scan.room)
                home.landmarks = [lm for lm in home.landmarks if lm.room != scan.room]
            latest = max(others, key=lambda s: s.created_at, default=None)
            if latest is None:
                home.room_model = None
            elif latest.created_at < scan.created_at:
                home.room_model = self._room_model(latest) or home.room_model
            if home.first_scan_id == scan.id:
                home.first_scan_id = min(others, key=lambda s: s.created_at).id if others else None
            self.homes.save(home)

        self.scans.delete(scan.id)
        self.blobs.delete_prefix(scan.folder)
        self.remove_files(scan.folder)
        self.audit(Action.SCAN_ERASED, actor, target_type="scan", target_id=scan.id, room=scan.room,
                   things_forgotten=forgotten, things_restored=restored, furniture_removed=furniture)  # fmt: skip
        return Erased(scan.id, forgotten, restored, furniture)

    def _room_model(self, scan: Scan) -> RoomModel | None:
        """The room shape the pipeline found for an earlier scan, from its stored result."""
        key = f"{scan.folder}/episode/result.json"
        if not self.blobs.exists(key):
            return None
        return RoomModel.from_dict(json.loads(self.blobs.get(key))["room"])
