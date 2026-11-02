"""Replays real scans through the photo matcher (evals/results.md, "Recognising the room from a photo").

    cd services/api && uv run python ../../evals/locate_photo.py REFERENCE_SCAN_ID [OTHER_SCAN_ID ...]

Needs the scans on this Mac (data/blobs/scans) with their place indexes (`make place-index`). Prints the held-out
accuracy on the reference scan, then for each other scan the fix rate and the share of fixes that agree with the
consensus scan-to-scan transform.
"""

from __future__ import annotations

import json
import sys
import tempfile
import time
from pathlib import Path

import numpy as np

from recall_api.adapters.outbound.vision.orb_place_matcher import OrbPlaceMatcher
from recall_api.application.ports import PlaceQuery

SCANS = Path(__file__).resolve().parents[1] / "data" / "blobs" / "scans"


class Disk:
    def local_path(self, key):
        return key


def episode(prefix: str) -> Path:
    return next(SCANS.glob(f"*_{prefix}*/episode"))


def poses(ep: Path) -> dict[int, np.ndarray]:
    out = {}
    for line in (ep / "poses.jsonl").read_text().splitlines():
        p = json.loads(line)
        out[p["index"]] = np.array(p["pose"], float).reshape(4, 4).T
    return out


def query(ep: Path, i: int) -> PlaceQuery:
    k = json.loads((ep / "manifest.json").read_text())["intrinsics"]
    return PlaceQuery((ep / "frames" / f"{i:06d}.jpg").read_bytes(), k["fx"], k["fy"], k["cx"], k["cy"])


def angle(a: np.ndarray, b: np.ndarray) -> float:
    d = a[:3, :3].T @ b[:3, :3]
    return float(np.degrees(np.arccos(np.clip((np.trace(d) - 1) / 2, -1, 1))))


def fixed(r) -> bool:
    return bool(r) and r[0].pose is not None and r[0].inliers >= 30 and r[0].reproj_px <= 4


def held_out(matcher: OrbPlaceMatcher, ep: Path, out: Path) -> None:
    z = dict(np.load(ep / "place_index.npz"))
    ids = z["frame_ids"]
    rows = np.arange(len(ids))[1::2]  # the index keeps every other keyframe; the rest are the photos
    sel = np.isin(z["frame"], rows)
    remap = {r: k for k, r in enumerate(rows)}
    sub = {**z, "desc": z["desc"][sel], "xyz": z["xyz"][sel], "frame": np.array([remap[f] for f in z["frame"][sel]]),
           "frame_ids": ids[rows], "poses": z["poses"][rows]}  # fmt: skip
    np.savez(out / "held.npz", **sub)
    truth = poses(ep)
    errs, angs, times = [], [], []
    photos = [int(ids[r]) for r in range(0, len(ids), 2)]
    for i in photos:
        t = time.perf_counter()
        r = matcher.match(query(ep, i), {"held": str(out / "held.npz")})
        times.append(time.perf_counter() - t)
        if fixed(r):
            P = np.array(r[0].pose).reshape(4, 4).T
            errs.append(np.linalg.norm(P[:3, 3] - truth[i][:3, 3]))
            angs.append(angle(P, truth[i]))
    print(f"held-out: {len(errs)}/{len(photos)} fixes; {np.median(errs) * 100:.1f} cm median, "
          f"{np.percentile(errs, 90) * 100:.1f} cm p90; {np.median(angs):.2f} deg median; "
          f"{np.median(times) * 1000:.0f} ms median")  # fmt: skip


def other_session(matcher: OrbPlaceMatcher, ref: Path, other: Path) -> None:
    truth = poses(other)
    photos = [i for i in sorted(truth)[::3] if (other / "frames" / f"{i:06d}.jpg").exists()]
    Ts = []
    for i in photos:
        r = matcher.match(query(other, i), {"ref": str(ref / "place_index.npz")})
        if fixed(r):
            Ts.append(np.array(r[0].pose).reshape(4, 4).T @ np.linalg.inv(truth[i]))

    def close(a, b):
        return np.linalg.norm(a[:3, 3] - b[:3, 3]) < 0.25 and angle(a, b) < 10

    if not Ts:
        print(f"{other.parent.name[:40]}: 0/{len(photos)} fixes")
        return
    best = Ts[int(np.argmax([sum(close(a, b) for b in Ts) for a in Ts]))]
    right = sum(close(best, t) for t in Ts)
    print(f"{other.parent.name[:40]}: {len(Ts)}/{len(photos)} fixes, {right} right")


def main(argv: list[str]) -> int:
    matcher = OrbPlaceMatcher(Disk())
    ref = episode(argv[0])
    with tempfile.TemporaryDirectory() as d:
        held_out(matcher, ref, Path(d))
    for o in argv[1:]:
        other_session(matcher, ref, episode(o))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
