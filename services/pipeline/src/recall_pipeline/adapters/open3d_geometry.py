"""Classic point-cloud geometry with Open3D: clean-up, RANSAC planes, DBSCAN. No Open3D-ML."""

from __future__ import annotations

import numpy as np
import open3d as o3d

from recall_pipeline.application.ports import Plane


def _pcd(points: np.ndarray) -> o3d.geometry.PointCloud:
    p = o3d.geometry.PointCloud()
    p.points = o3d.utility.Vector3dVector(points.astype(np.float64))
    return p


class Open3DGeometry:
    def __init__(
        self,
        voxel: float = 0.02,
        nb_neighbors: int = 20,
        std_ratio: float = 2.0,
        plane_dist: float = 0.03,
        max_walls: int = 8,
        min_wall_points: int = 800,
        seed: int = 7,
    ) -> None:
        self.voxel, self.nb, self.std = voxel, nb_neighbors, std_ratio
        self.plane_dist, self.max_walls, self.min_wall_points = plane_dist, max_walls, min_wall_points
        o3d.utility.random.seed(seed)  # RANSAC is seeded: same input, same planes

    def clean(self, points: np.ndarray) -> np.ndarray:
        pcd = _pcd(points).voxel_down_sample(self.voxel)
        pcd, _ = pcd.remove_statistical_outlier(nb_neighbors=self.nb, std_ratio=self.std)
        return np.asarray(pcd.points)

    def floor_and_walls(self, points: np.ndarray) -> tuple[Plane, list[Plane]]:
        """Points are z-up. Floor: the lowest large near-horizontal plane; walls: near-vertical, largest first."""
        rest = _pcd(points)
        floor: Plane | None = None
        walls: list[Plane] = []
        horizontals: list[Plane] = []
        for _ in range(self.max_walls + 6):
            if len(rest.points) < self.min_wall_points:
                break
            model, idx = rest.segment_plane(distance_threshold=self.plane_dist, ransac_n=3, num_iterations=2000)
            inl = np.asarray(rest.select_by_index(idx).points)
            n = np.asarray(model[:3], float)
            n /= np.linalg.norm(n)
            if abs(n[2]) > 0.9:  # horizontal: floor, ceiling or a table top
                if n[2] < 0:
                    n, d = -n, -model[3]
                else:
                    d = model[3]
                horizontals.append(Plane(n, float(d), inl))
            elif abs(n[2]) < 0.2 and len(inl) >= self.min_wall_points:
                walls.append(Plane(n, float(model[3]), inl))
            rest = rest.select_by_index(idx, invert=True)
            if len(walls) >= self.max_walls:
                break
        if horizontals:
            big = [h for h in horizontals if len(h.inliers) >= 0.3 * max(len(x.inliers) for x in horizontals)]
            floor = min(big, key=lambda h: float(np.median(h.inliers[:, 2])))
        if floor is None:
            raise ValueError("no floor plane found: the scan needs to see the floor")
        return floor, walls

    def clusters(self, points: np.ndarray, eps: float, min_points: int) -> np.ndarray:
        return np.asarray(_pcd(points).cluster_dbscan(eps=eps, min_points=min_points))
