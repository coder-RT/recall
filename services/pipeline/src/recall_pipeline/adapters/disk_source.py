"""Reads an episode folder from the Mac's disk."""

from __future__ import annotations

import io
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from recall_pipeline.domain.episode import Episode


class DiskEpisodeSource:
    def __init__(self, folder: str | Path, min_confidence: int = 1) -> None:
        self.folder = Path(folder)
        self.min_confidence = min_confidence  # ARKit depth confidence: 0 low, 1 medium, 2 high

    def load(self) -> Episode:
        manifest = json.loads((self.folder / "manifest.json").read_text())
        lines = [json.loads(x) for x in (self.folder / "poses.jsonl").read_text().splitlines() if x.strip()]
        return Episode.from_records(manifest, lines)

    def _name(self, index: int) -> str:
        return f"{index:06d}"

    def jpeg(self, index: int) -> bytes:
        return (self.folder / "frames" / f"{self._name(index)}.jpg").read_bytes()

    def image_rgb(self, index: int) -> np.ndarray:
        return np.asarray(Image.open(io.BytesIO(self.jpeg(index))).convert("RGB"))

    def depth_m(self, index: int, size: tuple[int, int]) -> np.ndarray:
        raw = cv2.imread(str(self.folder / "depth" / f"{self._name(index)}.png"), cv2.IMREAD_UNCHANGED)
        if raw is None or raw.dtype != np.uint16:
            raise ValueError(f"depth {index} is not a 16-bit PNG")
        depth = raw.astype(np.float32) / 1000.0
        conf_path = self.folder / "confidence" / f"{self._name(index)}.png"
        if conf_path.exists():
            conf = cv2.imread(str(conf_path), cv2.IMREAD_UNCHANGED)
            depth[conf < self.min_confidence] = 0.0
        return cv2.resize(depth, size, interpolation=cv2.INTER_NEAREST)  # nearest: never blend across edges

    def sharpness(self, index: int) -> float:
        """Variance of the Laplacian on the grey image (OpenCV classic functions only)."""
        grey = cv2.cvtColor(self.image_rgb(index), cv2.COLOR_RGB2GRAY)
        return float(cv2.Laplacian(grey, cv2.CV_64F).var())
