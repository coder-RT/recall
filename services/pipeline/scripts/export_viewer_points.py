# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy>=2", "scipy>=1.14"]
# ///
"""Export a light point cloud for the web viewer from a MapAnything run.

Input: an .npz with per-view `pts` (OpenCV world frame), `mask`, `conf`, `img` (RGB), `poses`.
Output, in the home frame (floor z = 0, z up, metres): `points.bin` (little-endian float32 xyz),
`colors.bin` (uint8 rgb per point), `conf.bin` (uint8 per point, 0 = least, 255 = most confident) and
`meta.json` (count, bounds, horizontal surfaces found by geometry, the run's measured stats).

    uv run services/pipeline/scripts/export_viewer_points.py VIEWS.npz OUT_DIR --stats STATS.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from scipy import ndimage


def fit_floor(points: np.ndarray, up_hint: np.ndarray, rng: np.random.Generator) -> tuple[np.ndarray, float]:
    """RANSAC plane among the lowest points whose normal is near `up_hint`; returns (normal, offset) with n·p + d = height."""
    heights = points @ up_hint
    low = points[heights < np.percentile(heights, 15)]
    best_count, best = 0, None
    for _ in range(3000):
        a, b, c = low[rng.choice(len(low), 3, replace=False)]
        n = np.cross(b - a, c - a)
        norm = np.linalg.norm(n)
        if norm < 1e-9:
            continue
        n = n / norm
        n = n if n @ up_hint > 0 else -n
        if n @ up_hint < 0.9:
            continue
        count = int((np.abs((low - a) @ n) < 0.015).sum())
        if count > best_count:
            best_count, best = count, (n, a)
    if best is None:
        raise SystemExit("no floor plane found")
    n, a = best
    inliers = low[np.abs((low - a) @ n) < 0.015]
    centre = inliers.mean(0)
    n = np.linalg.svd(inliers - centre)[2][-1]
    n = n if n @ up_hint > 0 else -n
    return n, float(-n @ centre)


def to_home_frame(points: np.ndarray, normal: np.ndarray, offset: float) -> np.ndarray:
    """Rotate so the floor normal is +z and the floor is z = 0, then centre x/y on the room."""
    x = np.cross([0.0, 0.0, 1.0], normal) if abs(normal[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    x = x - (x @ normal) * normal
    x /= np.linalg.norm(x)
    y = np.cross(normal, x)
    rot = np.stack([x, y, normal])  # rows: new axes
    out = points @ rot.T
    out[:, 2] += offset
    lo, hi = np.percentile(out[:, :2], 1, axis=0), np.percentile(out[:, :2], 99, axis=0)
    out[:, :2] -= (lo + hi) / 2
    return out


def voxel_downsample(points: np.ndarray, voxel: float) -> np.ndarray:
    """Indices of one point per voxel (the first seen), in the original order."""
    keys = np.floor(points / voxel).astype(np.int64)
    _, idx = np.unique(keys, axis=0, return_index=True)
    return np.sort(idx)


def find_surfaces(points: np.ndarray, cell: float = 0.05, slab: float = 0.015, min_area: float = 0.12) -> list[dict]:
    """Horizontal surfaces (desk tops, shelf levels, seats): flat patches at the heights where points pile up.

    Geometry only; nothing is named. Thin lines (walls crossing the slab) are rejected by fill ratio.
    """
    z = points[:, 2]
    bins = np.arange(0.15, z.max(), 0.01)
    hist, _ = np.histogram(z, bins=bins)
    found = []
    for i in range(3, len(hist) - 3):
        if hist[i] < 0.004 * len(points) or hist[i] < hist[i - 3 : i + 4].max():
            continue
        zc = bins[i] + 0.005
        pts = points[np.abs(z - zc) < slab]
        lo = pts[:, :2].min(0)
        ij = np.floor((pts[:, :2] - lo) / cell).astype(int)
        grid = np.zeros(ij.max(0) + 1, dtype=bool)
        grid[ij[:, 0], ij[:, 1]] = True
        labels, n = ndimage.label(grid)
        for k in range(1, n + 1):
            cells = np.argwhere(labels == k)
            area = len(cells) * cell * cell
            if area < min_area:
                continue
            cmin, cmax = cells.min(0), cells.max(0) + 1
            fill = len(cells) / float((cmax - cmin).prod())
            if fill < 0.35:
                continue
            found.append({
                "z": round(float(zc), 3),
                "min": np.round(lo + cmin * cell, 3).tolist(),
                "max": np.round(lo + cmax * cell, 3).tolist(),
                "area_m2": round(float(area), 2),
                "points": int(len(cells)),
            })
    found.sort(key=lambda f: -f["area_m2"])
    return found


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("views", type=Path)
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--stats", type=Path, help="JSON with the run's measured stats, copied into meta.json")
    ap.add_argument("--target", type=int, default=150_000, help="approximate number of points to keep")
    args = ap.parse_args()

    data = np.load(args.views)
    mask = data["mask"]
    points = data["pts"][mask].astype(np.float64)
    colors = data["img"][mask]
    conf = data["conf"][mask].astype(np.float32)
    up_hint = -data["poses"][:, :3, 1].mean(0)  # OpenCV camera +Y is down
    up_hint /= np.linalg.norm(up_hint)

    rng = np.random.default_rng(0)
    sample = points[rng.choice(len(points), min(400_000, len(points)), replace=False)]
    normal, offset = fit_floor(sample, up_hint, rng)
    home = to_home_frame(points, normal, offset)

    # drop stray points far outside the room, then grow the voxel until we are near the target count
    lo, hi = np.percentile(home, 0.5, axis=0), np.percentile(home, 99.5, axis=0)
    inside = np.all((home >= lo) & (home <= hi), axis=1) & (home[:, 2] > -0.05)
    home, colors, conf = home[inside], colors[inside], conf[inside]
    voxel = 0.02
    idx = voxel_downsample(home, voxel)
    while len(idx) > args.target:
        voxel *= 1.15
        idx = voxel_downsample(home, voxel)
    kept = home[idx]

    # confidence to 0..255 by rank within this room (the raw value is unbounded above 1)
    conf_u8 = np.clip((conf[idx] - 1.0) / max(float(np.percentile(conf, 99)) - 1.0, 1e-6), 0, 1) * 255

    surfaces = find_surfaces(home[voxel_downsample(home, 0.02)])

    args.out_dir.mkdir(parents=True, exist_ok=True)
    kept.astype("<f4").tofile(args.out_dir / "points.bin")
    colors[idx].astype(np.uint8).tofile(args.out_dir / "colors.bin")
    conf_u8.astype(np.uint8).tofile(args.out_dir / "conf.bin")
    meta = {
        "count": int(len(kept)),
        "voxel_m": round(voxel, 4),
        "frame": "home: floor z = 0, z up, metres",
        "bounds": {"min": np.round(kept.min(0), 3).tolist(), "max": np.round(kept.max(0), 3).tolist()},
        "surfaces": surfaces,
        "stats": json.loads(args.stats.read_text()) if args.stats else {},
    }
    (args.out_dir / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"{len(kept)} points, voxel {voxel:.3f} m, bounds {meta['bounds']}")
    for f in surfaces:
        print(f"  surface at z={f['z']:.2f} m: {f['max'][0]-f['min'][0]:.2f} x {f['max'][1]-f['min'][1]:.2f} m, {f['area_m2']} m2")


if __name__ == "__main__":
    main()
