"""What the pipeline needs from the outside world. Adapters implement these."""

from __future__ import annotations

from typing import Any, Protocol

import numpy as np

from recall_pipeline.domain.episode import Episode


class EpisodeSource(Protocol):
    """Reads an episode folder (the Mac's disk today; R2 later)."""

    def load(self) -> Episode: ...
    def image(self, index: int) -> bytes: ...
    def depth_mm(self, index: int) -> np.ndarray: ...
    def confidence(self, index: int) -> np.ndarray: ...


class Reconstructor(Protocol):
    """MapAnything: per-frame metric points in the ARKit world frame."""

    def reconstruct(self, episode: Episode, source: EpisodeSource, indices: list[int]) -> dict[str, Any]: ...


class Segmenter(Protocol):
    """SAM 3.1: masks for text prompts on one frame."""

    def segment(self, jpeg: bytes, prompts: list[str]) -> list[dict[str, Any]]: ...


class ResultSink(Protocol):
    """Posts the results to the API (the only writer of memory)."""

    def post(self, scan_id: str, result: dict[str, Any]) -> None: ...
