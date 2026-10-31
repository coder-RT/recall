"""Paint the scan's own photos onto its surface mesh (projective texturing; nothing is generated).

Every triangle takes the photo that sees it best: the centroid has to land inside the image, face the camera and not
be hidden behind something nearer (checked against that frame's LiDAR depth). Among those, a frontal, close, sharp
view wins. One smoothing pass then hands a triangle to its neighbours' photo when that photo sees it nearly as well,
so the surface changes photo less often (fewer seams). The photos are tiled into one atlas; triangles no photo sees
keep the mesh's vertex colours.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class Camera:
    """One keyframe: OpenCV camera-to-world (+X right, +Y down, +Z forward) in the same frame as the mesh."""

    K: np.ndarray  # 3x3 intrinsics for the saved image size
    cam2world: np.ndarray  # 4x4
    width: int
    height: int
    depth_m: np.ndarray | None = None  # LiDAR depth for this frame (any resolution, metres; 0 = unknown)
    sharpness: float = 1.0  # relative: 1 = the scan's median frame


@dataclass(frozen=True)
class TexturedMesh:
    positions: np.ndarray  # (V, 3) float32
    uvs: np.ndarray  # (V, 2) float32, atlas coordinates, v = 1 at the atlas top (three.js flipY)
    index: np.ndarray  # (T1, 3) uint32: photo-textured triangles
    rest_index: np.ndarray  # (T2, 3) uint32: triangles no photo sees (draw with `colors`)
    colors: np.ndarray  # (V, 3) uint8 vertex colours (for the rest)
    frames: list[int]  # camera index of each atlas tile, in tile order
    grid: tuple[int, int]  # atlas columns, rows

    @property
    def textured_share(self) -> float:
        n = len(self.index) + len(self.rest_index)
        return len(self.index) / n if n else 0.0


def project(cam: Camera, pts: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Pixel coordinates (N, 2) and depth along the optical axis (N,) of world points."""
    world2cam = np.linalg.inv(cam.cam2world)
    p = pts @ world2cam[:3, :3].T + world2cam[:3, 3]
    z = p[:, 2]
    safe = np.where(np.abs(z) < 1e-6, 1e-6, z)
    uv = (p[:, :2] / safe[:, None]) @ cam.K[:2, :2].T + cam.K[:2, 2]
    return uv, z


def view_scores(
    cam: Camera, centroids: np.ndarray, normals: np.ndarray, margin: float = 8.0, min_cos: float = 0.2
) -> np.ndarray:
    """How well this camera sees each triangle (0 = not at all)."""
    uv, z = project(cam, centroids)
    inside = (z > 0.1) & (uv[:, 0] >= margin) & (uv[:, 0] < cam.width - margin)
    inside &= (uv[:, 1] >= margin) & (uv[:, 1] < cam.height - margin)
    to_cam = cam.cam2world[:3, 3] - centroids
    dist = np.linalg.norm(to_cam, axis=1)
    cos = np.abs(np.einsum("ij,ij->i", normals, to_cam / np.maximum(dist, 1e-6)[:, None]))
    ok = inside & (cos > min_cos)
    if cam.depth_m is not None:
        dh, dw = cam.depth_m.shape
        u = np.clip((uv[:, 0] * dw / cam.width).astype(int), 0, dw - 1)
        v = np.clip((uv[:, 1] * dh / cam.height).astype(int), 0, dh - 1)
        d = cam.depth_m[v, u]
        known = d > 0
        hidden = known & (z > d + 0.05 + 0.03 * d)  # something nearer stands between the camera and the triangle
        ok &= ~hidden
    score = cos * cam.sharpness / np.maximum(dist, 0.3)
    return np.where(ok, score, 0.0)


def neighbours(triangles: np.ndarray) -> np.ndarray:
    """(T, 3) the triangle across each edge, or -1 at the border."""
    t = len(triangles)
    edges = np.concatenate([triangles[:, [0, 1]], triangles[:, [1, 2]], triangles[:, [2, 0]]])
    edges.sort(axis=1)
    owner = np.tile(np.arange(t), 3)
    slot = np.repeat(np.arange(3), t)
    order = np.lexsort((edges[:, 1], edges[:, 0]))
    e, o, s = edges[order], owner[order], slot[order]
    same = np.all(e[1:] == e[:-1], axis=1)
    out = np.full((t, 3), -1, dtype=np.int64)
    i = np.nonzero(same)[0]
    out[o[i], s[i]] = o[i + 1]
    out[o[i + 1], s[i + 1]] = o[i]
    return out


def choose_views(scores: np.ndarray, triangles: np.ndarray, passes: int = 2, keep: float = 0.6) -> np.ndarray:
    """The camera for each triangle (-1 = none), smoothed towards its neighbours' choice."""
    best = np.where(scores.max(1) > 0, scores.argmax(1), -1)
    nb = neighbours(triangles)
    rows = np.arange(len(best))
    for _ in range(passes):
        cand = np.where(nb >= 0, best[np.maximum(nb, 0)], -1)  # (T, 3) neighbours' cameras
        # the camera at least two neighbours agree on
        agree = np.where(
            (cand[:, 0] == cand[:, 1]) | (cand[:, 0] == cand[:, 2]),
            cand[:, 0],
            np.where(cand[:, 1] == cand[:, 2], cand[:, 1], -1),
        )
        own = np.where(best >= 0, scores[rows, np.maximum(best, 0)], 0.0)
        theirs = np.where(agree >= 0, scores[rows, np.maximum(agree, 0)], 0.0)
        switch = (agree >= 0) & (agree != best) & (theirs > 0) & (theirs >= keep * own)
        best = np.where(switch, agree, best)
    return best


def exposure_gains(mean_luminance: np.ndarray, lo: float = 0.7, hi: float = 1.4) -> np.ndarray:
    """Per-photo brightness gain towards the median, so neighbouring photos match."""
    target = float(np.median(mean_luminance))
    return np.clip(target / np.maximum(mean_luminance, 1e-3), lo, hi)


def atlas_grid(n: int) -> tuple[int, int]:
    """Columns and rows for n tiles, close to square in pixels for 4:3 tiles."""
    cols = max(1, int(np.ceil(np.sqrt(n * 3 / 4))))
    return cols, int(np.ceil(n / cols))


def texture(
    vertices: np.ndarray, triangles: np.ndarray, vertex_colors: np.ndarray, cameras: list[Camera]
) -> TexturedMesh:
    v = vertices[triangles]
    centroids = v.mean(1)
    n = np.cross(v[:, 1] - v[:, 0], v[:, 2] - v[:, 0])
    normals = n / np.maximum(np.linalg.norm(n, axis=1), 1e-12)[:, None]
    scores = np.stack([view_scores(c, centroids, normals) for c in cameras], axis=1)
    best = choose_views(scores, triangles)

    used = sorted(set(best[best >= 0].tolist()))
    tile_of = {c: i for i, c in enumerate(used)}
    cols, rows = atlas_grid(len(used))

    seen = best >= 0
    tris = triangles[seen]
    cams = best[seen]
    # one vertex per (mesh vertex, camera): only seams between photos duplicate a vertex
    key = tris.astype(np.int64) * len(cameras) + cams[:, None]
    uniq, inverse = np.unique(key.ravel(), return_inverse=True)
    src_vertex = uniq // len(cameras)
    src_cam = uniq % len(cameras)
    uv = np.zeros((len(uniq), 2))
    for c in np.unique(src_cam):
        m = src_cam == c
        cam = cameras[c]
        px, _ = project(cam, vertices[src_vertex[m]])
        px[:, 0] = np.clip(px[:, 0], 0.5, cam.width - 0.5)
        px[:, 1] = np.clip(px[:, 1], 0.5, cam.height - 0.5)
        col, row = tile_of[int(c)] % cols, tile_of[int(c)] // cols
        uv[m, 0] = (col + px[:, 0] / cam.width) / cols
        uv[m, 1] = 1.0 - (row + px[:, 1] / cam.height) / rows

    # the rest keep their vertex colours, appended after the textured vertices
    rest = triangles[~seen]
    rest_vertices, rest_inverse = np.unique(rest.ravel(), return_inverse=True)
    base = len(uniq)
    positions = np.concatenate([vertices[src_vertex], vertices[rest_vertices]]).astype(np.float32)
    uvs = np.concatenate([uv, np.zeros((len(rest_vertices), 2))]).astype(np.float32)
    colors = np.concatenate([vertex_colors[src_vertex], vertex_colors[rest_vertices]]).astype(np.uint8)
    return TexturedMesh(
        positions=positions,
        uvs=uvs,
        index=inverse.reshape(-1, 3).astype(np.uint32),
        rest_index=(rest_inverse.reshape(-1, 3) + base).astype(np.uint32),
        colors=colors,
        frames=used,
        grid=(cols, rows),
    )
