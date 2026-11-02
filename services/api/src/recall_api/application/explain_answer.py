"""Why Recall said what it said: a logged answer, followed back through its tool results to the sightings, their
keyframes and scans, and the models that made them. Read-only."""

from __future__ import annotations

from recall_api.application.ports import AnswerLog, BlobStore, ImageCropper
from recall_api.domain.ports import ScanRepository, TrackedObjectRepository


class EvidenceError(Exception):
    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


CROP_MARGIN = 0.25  # around the box, so the thing is seen in its place


def widen(box: tuple[float, float, float, float], margin: float = CROP_MARGIN) -> tuple[float, float, float, float]:
    """The box grown by `margin` of its size on each side, never below 0 (the cropper clamps the far edges)."""
    x1, y1, x2, y2 = box
    mx, my = (x2 - x1) * margin, (y2 - y1) * margin
    return max(0.0, x1 - mx), max(0.0, y1 - my), x2 + mx, y2 + my


class ExplainAnswer:
    def __init__(
        self,
        answers: AnswerLog,
        objects: TrackedObjectRepository,
        scans: ScanRepository,
        blobs: BlobStore,
        cropper: ImageCropper,
    ) -> None:
        self.answers, self.objects, self.scans, self.blobs = answers, objects, scans, blobs
        self.cropper = cropper

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

    def crop(self, observation_id: str) -> bytes:
        """The camera's view of a sighting: its keyframe cut to the box with a margin (no extra file is stored)."""
        obj = self.objects.get_by_observation(observation_id)
        o = next((x for x in obj.observations if x.id == observation_id), None) if obj else None
        scan = self.scans.get(o.scan_id) if o else None
        key = self._frame(scan, o) if o else None
        if key is None:
            raise EvidenceError("No camera view is kept for this sighting.")
        return self.cropper.crop(self.blobs.get(key), widen(o.box))

    def _frame(self, scan, o) -> str | None:
        if scan is None or o.keyframe_index is None or o.box is None:
            return None
        key = f"{scan.folder}/episode/frames/{o.keyframe_index:06d}.jpg"
        return key if self.blobs.exists(key) else None
