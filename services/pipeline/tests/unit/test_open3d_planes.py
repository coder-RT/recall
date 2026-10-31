"""Plane fitting on a synthetic room: the floor at z = 0 and four walls within 10 cm (CLAUDE.md item 10b)."""

import numpy as np
import pytest

o3d_geometry = pytest.importorskip("recall_pipeline.adapters.open3d_geometry")  # Open3D isn't installed in CI


def synthetic_room(rng, noise=0.01):
    n = 6000
    floor = np.c_[rng.uniform(0, 4, n), rng.uniform(0, 3, n), rng.normal(0, noise, n)]
    walls = [
        np.c_[np.full(n, 0.0) + rng.normal(0, noise, n), rng.uniform(0, 3, n), rng.uniform(0, 2.5, n)],
        np.c_[np.full(n, 4.0) + rng.normal(0, noise, n), rng.uniform(0, 3, n), rng.uniform(0, 2.5, n)],
        np.c_[rng.uniform(0, 4, n), np.full(n, 0.0) + rng.normal(0, noise, n), rng.uniform(0, 2.5, n)],
        np.c_[rng.uniform(0, 4, n), np.full(n, 3.0) + rng.normal(0, noise, n), rng.uniform(0, 2.5, n)],
    ]
    table = np.c_[rng.uniform(1, 2, 2000), rng.uniform(1, 2, 2000), np.full(2000, 0.75)]
    return np.concatenate([floor, *walls, table])


def test_floor_and_four_walls_within_ten_centimetres():
    geo = o3d_geometry.Open3DGeometry(voxel=0.03)
    pts = geo.clean(synthetic_room(np.random.default_rng(0)))
    floor, walls = geo.floor_and_walls(pts)
    assert abs(np.median(floor.inliers[:, 2])) < 0.02  # the floor, not the table top
    found = sorted(round(-w.d / (w.normal[0] if abs(w.normal[0]) > 0.9 else w.normal[1]), 2) for w in walls[:4])
    expected = sorted([0.0, 4.0, 0.0, 3.0])
    assert len(walls) >= 4
    assert all(abs(abs(f) - e) < 0.10 for f, e in zip(sorted(map(abs, found)), expected, strict=True))


def test_dbscan_merges_repeated_sightings_of_one_object():
    geo = o3d_geometry.Open3DGeometry()
    rng = np.random.default_rng(2)
    mug = rng.normal([1.0, 1.0, 0.8], 0.02, (30, 3))
    keys = rng.normal([3.0, 0.5, 1.2], 0.02, (5, 3))
    labels = geo.clusters(np.concatenate([mug, keys]), eps=0.25, min_points=1)
    assert len(set(labels[:30])) == 1 and len(set(labels[30:])) == 1 and labels[0] != labels[30]
