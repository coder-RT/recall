"""ImageCropper with Pillow: cuts a sighting's box out of its keyframe (no model involved)."""

from __future__ import annotations

import io

from PIL import Image


class PillowCropper:
    def __init__(self, quality: int = 85) -> None:
        self.quality = quality

    def crop(self, jpeg: bytes, box: tuple[float, float, float, float]) -> bytes:
        image = Image.open(io.BytesIO(jpeg))
        x1, y1, x2, y2 = box
        clamped = (max(0, int(x1)), max(0, int(y1)), min(image.width, int(x2)), min(image.height, int(y2)))
        out = io.BytesIO()
        image.crop(clamped).convert("RGB").save(out, "JPEG", quality=self.quality)
        return out.getvalue()
