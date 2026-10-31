"""One landmark per piece of furniture. SAM answers per prompt, so one desk comes back as both "table" and "desk",
and a big desk seen from several sides becomes several small boxes. Boxes of the same kind that overlap or
touch on the floor plan (and share height) are merged into one, named after the label with the most evidence."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

# labels that name the same kind of thing; anything else only merges with its own label
SAME_KIND = ({"table", "desk"},)
TOUCH_M = 0.10  # boxes closer than this on the floor plan count as touching


@dataclass
class Piece:
    label: str
    lo: np.ndarray  # bbox min (x, y, z), home frame
    hi: np.ndarray
    confidence: float
    sightings: int
    keyframe_index: int
    points: np.ndarray


def _kind(label: str) -> str:
    for group in SAME_KIND:
        if label in group:
            return "/".join(sorted(group))
    return label


def _touch(a: Piece, b: Piece) -> bool:
    gap_xy = np.maximum(0, np.maximum(a.lo[:2] - b.hi[:2], b.lo[:2] - a.hi[:2]))
    z_overlap = min(a.hi[2], b.hi[2]) - max(a.lo[2], b.lo[2])
    return float(np.linalg.norm(gap_xy)) <= TOUCH_M and z_overlap > 0


def merge(pieces: list[Piece]) -> list[tuple[Piece, list[str]]]:
    """Merged pieces with every label that went into each (most evidence first)."""
    parent = list(range(len(pieces)))

    def root(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(pieces)):
        for j in range(i + 1, len(pieces)):
            if _kind(pieces[i].label) == _kind(pieces[j].label) and _touch(pieces[i], pieces[j]):
                parent[root(i)] = root(j)
    groups: dict[int, list[Piece]] = {}
    for i, p in enumerate(pieces):
        groups.setdefault(root(i), []).append(p)

    out = []
    for members in groups.values():
        evidence: dict[str, float] = {}
        for m in members:
            evidence[m.label] = evidence.get(m.label, 0.0) + m.confidence * m.sightings
        labels = sorted(evidence, key=evidence.get, reverse=True)
        best = max(members, key=lambda m: m.confidence)
        weights = np.array([m.sightings for m in members], float)
        out.append(
            (
                Piece(
                    label=labels[0],
                    lo=np.min([m.lo for m in members], axis=0),
                    hi=np.max([m.hi for m in members], axis=0),
                    confidence=float(np.average([m.confidence for m in members], weights=weights)),
                    sightings=int(weights.sum()),
                    keyframe_index=best.keyframe_index,
                    points=np.concatenate([m.points for m in members]),
                ),
                labels,
            )
        )
    return out
