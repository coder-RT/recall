"""Moved-object detection: match a new scan's detections to remembered objects of the same label (geometry only)."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy.optimize import linear_sum_assignment

from .model import Position


@dataclass(frozen=True)
class Match:
    existing: int | None  # index into the remembered objects, None = a new object
    detected: int | None  # index into the detections, None = not seen in this scan
    kind: str  # "same", "moved", "new", "gone", "out_of_view"
    distance_m: float | None


def match_label(
    remembered: list[Position], detected: list[Position], covered, moved_m: float = 0.30, max_pair_m: float = 3.0
) -> list[Match]:
    """Hungarian assignment on 3D distance. Within `moved_m` → same place; further (up to `max_pair_m`) → moved.

    A remembered object with no partner is "gone" only if `covered(position)` says this scan saw that spot;
    otherwise it is "out_of_view" and its memory stands.
    """
    out: list[Match] = []
    used_r, used_d = set(), set()
    if remembered and detected:
        cost = np.array([[r.distance_to(d) for d in detected] for r in remembered])
        rows, cols = linear_sum_assignment(cost)
        for r, d in zip(rows, cols, strict=True):
            dist = float(cost[r, d])
            if dist > max_pair_m:
                continue
            out.append(Match(int(r), int(d), "same" if dist <= moved_m else "moved", dist))
            used_r.add(int(r))
            used_d.add(int(d))
    for d in range(len(detected)):
        if d not in used_d:
            out.append(Match(None, d, "new", None))
    for r in range(len(remembered)):
        if r not in used_r:
            out.append(Match(r, None, "gone" if covered(remembered[r]) else "out_of_view", None))
    return out
