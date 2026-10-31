"""An object's colour as a basic colour name, from the photo pixels inside its box. Plain colour maths, no model:
each pixel gets the name of its hue, saturation and brightness range, and the most common name wins."""

from __future__ import annotations

import numpy as np

# the names the API accepts (domain COLOR_NAMES there); order is irrelevant
NAMES = ("black", "white", "grey", "red", "orange", "yellow", "green", "blue", "purple", "pink", "brown", "beige")


def pixel_names(rgb: np.ndarray) -> np.ndarray:
    """(N, 3) uint8 RGB → (N,) colour names."""
    c = rgb.reshape(-1, 3).astype(np.float32) / 255.0
    mx, mn = c.max(1), c.min(1)
    v, delta = mx, mx - mn
    s = np.where(mx > 0, delta / np.maximum(mx, 1e-6), 0)
    r, g, b = c[:, 0], c[:, 1], c[:, 2]
    d = np.maximum(delta, 1e-6)
    h = np.select([mx == r, mx == g], [((g - b) / d) % 6, (b - r) / d + 2], (r - g) / d + 4) * 60.0

    out = np.full(len(c), "grey", dtype=object)
    chromatic = (s >= 0.2) & (v >= 0.2)
    hue_names = [  # (from, to, name), degrees
        (0, 15, "red"), (15, 40, "orange"), (40, 70, "yellow"), (70, 170, "green"),
        (170, 255, "blue"), (255, 290, "purple"), (290, 345, "pink"), (345, 360, "red"),
    ]  # fmt: skip
    for lo, hi, name in hue_names:
        out[chromatic & (h >= lo) & (h < hi)] = name
    warm = (h >= 15) & (h < 50)
    out[chromatic & warm & (v < 0.6)] = "brown"
    out[(s >= 0.1) & (s < 0.35) & warm & (v >= 0.6)] = "beige"
    out[(s < 0.2) & (v >= 0.85)] = "white"
    out[v < 0.2] = "black"
    return out


def dominant_color(image: np.ndarray, box: tuple[float, float, float, float], inner: float = 0.5) -> str | None:
    """The most common colour name in the middle `inner` part of the box (edges are usually background)."""
    x1, y1, x2, y2 = box
    cx, cy, hw, hh = (x1 + x2) / 2, (y1 + y2) / 2, (x2 - x1) * inner / 2, (y2 - y1) * inner / 2
    h, w = image.shape[:2]
    xa, xb = int(max(0, cx - hw)), int(min(w, cx + hw + 1))
    ya, yb = int(max(0, cy - hh)), int(min(h, cy + hh + 1))
    crop = image[ya:yb, xa:xb]
    if crop.size < 3 * 16:
        return None
    names, counts = np.unique(pixel_names(crop), return_counts=True)
    return str(names[np.argmax(counts)])


def vote(colors: list[tuple[str | None, float]]) -> str | None:
    """One colour for a cluster of sightings: the name with the most score behind it."""
    tally: dict[str, float] = {}
    for name, score in colors:
        if name:
            tally[name] = tally.get(name, 0.0) + score
    return max(tally, key=tally.get) if tally else None
