"""Scan path: episode → MapAnything (metric ARKit inputs) → planes → SAM 3.1 boxes lifted to 3D → result."""

from __future__ import annotations

import time
from collections import defaultdict
from dataclasses import dataclass, field

import numpy as np

from recall_pipeline.application.ports import (
    DebugLog,
    EpisodeSource,
    PointCloudOps,
    Reconstructor,
    ResultSink,
    Segmenter,
)
from recall_pipeline.domain import home_frame, room_model
from recall_pipeline.domain.lift import lift_box


@dataclass
class PipelineConfig:
    max_views: int = 120  # MapAnything views per run (memory on the Mac)
    sam_every: int = 3  # SAM on every Nth reconstructed view
    min_score: float = 0.5
    furniture: tuple[str, ...] = ("sofa", "table", "desk", "shelf", "tv", "bed", "door", "chair", "cabinet")
    objects: tuple[str, ...] = (
        "keys",
        "wallet",
        "glasses",
        "phone",
        "remote control",
        "mug",
        "book",
        "laptop",
        "headphones",
        "backpack",
        "bottle",
        "charger",
        "watch",
        "passport",
        "bag",
    )
    cluster_eps: float = 0.25
    cluster_min: int = 1
    stats: dict = field(default_factory=dict)


def _subsample(n: int, k: int) -> list[int]:
    return list(range(n)) if n <= k else [int(round(i)) for i in np.linspace(0, n - 1, k)]


def process_episode(
    source: EpisodeSource,
    recon: Reconstructor,
    sam: Segmenter,
    geo: PointCloudOps,
    sink: ResultSink | None,
    debug: DebugLog,
    cfg: PipelineConfig | None = None,
) -> dict:
    cfg = cfg or PipelineConfig()
    t0 = time.perf_counter()
    episode = source.load()
    indices = _subsample(len(episode.frames), cfg.max_views)

    views = recon.reconstruct(episode, source, indices)
    t_recon = time.perf_counter() - t0
    world = np.concatenate([v.points[v.valid] for v in views])
    cloud = geo.clean(world)

    # planes in ARKit world (y up), then the home frame (z up, floor at 0)
    T_y = home_frame.Y_UP_TO_Z_UP
    floor, walls = geo.floor_and_walls(home_frame.apply(T_y, cloud))
    floor_z = float(np.median(floor.inliers[:, 2]))
    T = T_y.copy()
    T[2, 3] = -floor_z
    home_cloud = home_frame.apply(T, cloud)
    for v in views:
        debug.frame(v, source.image_rgb(v.index))
    debug.points("cloud", home_cloud)

    # SAM 3.1 boxes on a subset of views, lifted to 3D with depth + pose
    sightings: dict[str, list[tuple[np.ndarray, float, int, np.ndarray]]] = defaultdict(list)
    sam_views = views[:: cfg.sam_every]
    t1 = time.perf_counter()
    calls = 0
    for v in sam_views:
        jpeg = source.jpeg(v.index)
        h, w = v.depth.shape
        img_w, img_h = episode.image_size
        sx, sy = w / img_w, h / img_h  # SAM boxes are in source-image pixels; depth is at the output size
        for concept in cfg.furniture + cfg.objects:
            calls += 1
            for b in sam.boxes(jpeg, concept):
                if b.score < cfg.min_score:
                    continue
                box = (b.box[0] * sx, b.box[1] * sy, b.box[2] * sx, b.box[3] * sy)
                lifted = lift_box(
                    box, v.depth, v.intrinsics, v.cam2world, inner=0.9 if concept in cfg.furniture else 0.6
                )
                if lifted is None:
                    continue
                pts = home_frame.apply(T, lifted.points)
                sightings[concept].append((np.median(pts, axis=0), b.score, v.index, pts))
    t_sam = time.perf_counter() - t1

    # one thing per cluster of sightings of the same label
    things = {"landmarks": [], "objects": []}
    furniture_pts: list[tuple[str, np.ndarray]] = []
    for label, seen in sightings.items():
        centers = np.array([c for c, *_ in seen])
        labels = geo.clusters(centers, cfg.cluster_eps, cfg.cluster_min) if len(centers) > 1 else np.zeros(1, int)
        for k in sorted(set(labels.tolist()) - {-1}):
            members = [seen[i] for i in np.flatnonzero(labels == k)]
            pts = np.concatenate([m[3] for m in members])
            lo, hi = np.percentile(pts, 5, axis=0), np.percentile(pts, 95, axis=0)
            best = max(members, key=lambda m: m[1])
            thing = {
                "label": label,
                "centroid": np.round(np.median([m[0] for m in members], axis=0), 3).tolist(),
                "bbox_min": np.round(lo, 3).tolist(),
                "bbox_max": np.round(hi, 3).tolist(),
                "confidence": round(float(np.mean([m[1] for m in members])), 3),
                "sightings": len(members),
                "keyframe_index": int(best[2]),
            }
            if label in cfg.furniture:
                thing["front_dir"] = None
                things["landmarks"].append(thing)
                furniture_pts.append((label, pts))
            else:
                things["objects"].append(thing)

    floor_xy = home_frame.apply(T, home_frame.apply(np.linalg.inv(T_y), floor.inliers))  # back through T_y, then T
    wall_planes = []
    for w in walls:
        pts_home = home_frame.apply(T, home_frame.apply(np.linalg.inv(T_y), w.inliers))
        n = w.normal / np.linalg.norm(w.normal)
        d = -float(np.median(pts_home @ n))
        wall_planes.append(room_model.WallPlane(n, d, pts_home))
    room = room_model.room_json(room_model.floor_polygon(floor_xy), wall_planes, furniture_pts)

    if things["landmarks"] or things["objects"]:
        all_things = things["landmarks"] + things["objects"]
        c = np.array([t["centroid"] for t in all_things])
        half = (np.array([t["bbox_max"] for t in all_things]) - np.array([t["bbox_min"] for t in all_things])) / 2
        debug.boxes3d("things", c, half, [t["label"] for t in all_things])

    cfg.stats.update(
        {
            "views": len(views),
            "frames": len(episode.frames),
            "points": int(len(home_cloud)),
            "reconstruct_s": round(t_recon, 1),
            "sam_s": round(t_sam, 1),
            "sam_calls": calls,
            "walls": len(walls),
            "total_s": round(time.perf_counter() - t0, 1),
        }
    )
    result = {
        "scan_id": episode.scan_id,
        "room": room,
        "landmarks": things["landmarks"],
        "objects": things["objects"],
        "transform_to_home": T.reshape(-1).round(6).tolist(),
        "stats": cfg.stats,
    }
    if sink is not None:
        sink.post(episode.scan_id, result)
    return result
