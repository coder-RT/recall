"""Why Recall said what it said: a logged answer, followed back through its tool results to the sightings, their
keyframes and scans, and the models that made them. Read-only."""

from __future__ import annotations

from dataclasses import dataclass

from recall_api.application.ports import AnswerLog, BlobStore
from recall_api.domain.ports import ScanRepository, TrackedObjectRepository


class EvidenceError(Exception):
    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


@dataclass(frozen=True)
class CropSource:
    jpeg: bytes
    box: tuple[float, float, float, float]


class ExplainAnswer:
    def __init__(
        self, answers: AnswerLog, objects: TrackedObjectRepository, scans: ScanRepository, blobs: BlobStore
    ) -> None:
        self.answers, self.objects, self.scans, self.blobs = answers, objects, scans, blobs

    def __call__(self, answer_id: str) -> dict:
        a = self.answers.get(answer_id)
        if a is None:
            raise EvidenceError("No such answer.")
        sightings = []
        for oid in a.observation_ids:
            obj = self.objects.get_by_observation(oid)
            o = next((x for x in obj.observations if x.id == oid), None) if obj else None
            if obj is None or o is None:
                continue  # erased since: the chain says only what still exists
            scan = self.scans.get(o.scan_id)
            sightings.append({
                "observation_id": o.id,
                "object_id": obj.id,
                "label": obj.label,
                "position": list(o.position.as_tuple()),
                "confidence": round(o.confidence, 3),
                "seen_at": o.seen_at.isoformat(),
                "current": obj.is_current(o),
                "keyframe_index": o.keyframe_index,
                "box": list(o.box) if o.box else None,
                "crop_url": f"/observations/{o.id}/crop" if self._frame(scan, o) else None,
                "scan": {
                    "scan_id": o.scan_id,
                    "room": scan.room if scan else "",
                    "captured_at": (scan.created_at if scan else o.seen_at).isoformat(),
                    "provenance": scan.provenance if scan else None,
                },
            })  # fmt: skip
        return {
            "answer": {
                "answer_id": a.id,
                "question": a.question,
                "text": a.text,
                "grounded": a.grounded,
                "model": a.model,
                "provider": a.provider,
                "created_at": a.created_at.isoformat(),
                "latency_ms": a.latency_ms,
                "prompt_tokens": a.prompt_tokens,
                "completion_tokens": a.completion_tokens,
            },  # fmt: skip
            "steps": a.steps,
            "sightings": sightings,
        }

    def crop_source(self, observation_id: str) -> CropSource:
        """The keyframe and box where a sighting was made; the adapter cuts the crop (no extra file is stored)."""
        obj = self.objects.get_by_observation(observation_id)
        o = next((x for x in obj.observations if x.id == observation_id), None) if obj else None
        scan = self.scans.get(o.scan_id) if o else None
        key = self._frame(scan, o) if o else None
        if key is None:
            raise EvidenceError("No camera view is kept for this sighting.")
        return CropSource(self.blobs.get(key), o.box)

    def _frame(self, scan, o) -> str | None:
        if scan is None or o.keyframe_index is None or o.box is None:
            return None
        key = f"{scan.folder}/episode/frames/{o.keyframe_index:06d}.jpg"
        return key if self.blobs.exists(key) else None
