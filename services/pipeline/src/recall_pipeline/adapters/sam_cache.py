"""SAM 3.1 answers cached per scan (episode/cache/sam/), keyed by the frame's bytes and the prompt. A re-run of
the same scan (a geometry fix, the nightly regression) then makes no model calls and costs nothing."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from recall_pipeline.application.ports import Box, Segmenter


class CachedSegmenter:
    def __init__(self, inner: Segmenter, folder: Path) -> None:
        self.inner, self.folder = inner, folder
        self.folder.mkdir(parents=True, exist_ok=True)
        self.hits = self.misses = 0

    def boxes(self, jpeg: bytes, concept: str) -> list[Box]:
        key = hashlib.sha256(jpeg + b"\0" + concept.encode()).hexdigest()[:32]
        path = self.folder / f"{key}.json"
        if path.exists():
            self.hits += 1
            return [Box(b["label"], b["score"], tuple(b["box"])) for b in json.loads(path.read_text())]
        self.misses += 1
        found = self.inner.boxes(jpeg, concept)
        path.write_text(json.dumps([{"label": b.label, "score": b.score, "box": list(b.box)} for b in found]))
        return found
