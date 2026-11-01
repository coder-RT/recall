"""Scan path: episode → MapAnything (metric ARKit inputs) → planes → SAM 3.1 boxes lifted to 3D → result."""

from __future__ import annotations

import logging
import time
from collections import defaultdict
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import NamedTuple

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
from recall_pipeline.domain.appearance import dominant_color, vote
from recall_pipeline.domain.lift import lift_box
from recall_pipeline.domain.merge import ObjectCluster, Piece, merge, merge_objects

log = logging.getLogger("recall_pipeline")


class Sighting(NamedTuple):
    """One SAM box lifted into 3D: where, how sure, in which view, its points, its colour and its box in the photo."""

    center: np.ndarray  # median of its points, home frame
    score: float
    frame: int  # the view's keyframe index
    points: np.ndarray
    color: str | None
    box: tuple


@dataclass
class PipelineConfig:
    max_views: int = 120  # MapAnything views per run (memory on the Mac)
    sam_every: int = 3  # SAM on every Nth reconstructed view
    sam_workers: int = 8  # SAM calls in flight at once (the adapter backs off on 429; TODO(verify) the rate limit)
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
    segmenter: str = "sam-3.1"  # what the result says made the boxes (provenance)
    commit: str | None = None  # the pipeline's git commit, set by the wiring (provenance)
    cluster_eps: float = 0.25
    cluster_min: int = 1
    object_merge_m: float = 0.45  # clusters of one thing apart after a loop walk's drift (max 13 cm measured, ×3)
    stats: dict = field(default_factory=dict)


def _resample(image: np.ndarray, shape: tuple[int, int]) -> np.ndarray:
    """Nearest-neighbour resize of an (h, w, 3) image to `shape` (the view's output grid)."""
    h, w = shape
    rows = (np.arange(h) * image.shape[0] / h).astype(int)
    cols = (np.arange(w) * image.shape[1] / w).astype(int)
    return image[rows][:, cols]


def start_sam(
    pool: ThreadPoolExecutor, sam: Segmenter, source: EpisodeSource, frames: list[int], concepts: tuple[str, ...]
) -> dict[int, list[Future]]:
    """Submits every (frame, prompt) SAM call and returns at once: SAM needs only the photos, so its calls run while
    MapAnything reconstructs. Each frame's futures are in prompt order."""
    return {i: [pool.submit(sam.boxes, jpeg, c) for c in concepts] for i, jpeg in ((i, source.jpeg(i)) for i in frames)}


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
    log.info("episode %s: %d frames, reconstructing %d views", episode.scan_id, len(episode.frames), len(indices))

    # SAM 3.1 on every Nth view starts now, in the background, and overlaps the reconstruction
    concepts = cfg.furniture + cfg.objects
    pool = ThreadPoolExecutor(cfg.sam_workers)
    t1 = time.perf_counter()
    pending = start_sam(pool, sam, source, indices[:: cfg.sam_every], concepts)
    log.info(
        "SAM 3.1: %d views x %d prompts = %d calls, started", len(pending), len(concepts), len(pending) * len(concepts)
    )

    views = recon.reconstruct(episode, source, indices)
    t_recon = time.perf_counter() - t0
    log.info("reconstruction done in %.1f s", t_recon)
    world = np.concatenate([v.points[v.valid] for v in views])
    # each point's photo colour and MapAnything confidence follow it through the clean-up (for the viewer)
    rgb_all = np.concatenate([_resample(source.image_rgb(v.index), v.valid.shape)[v.valid] for v in views])
    conf_all = np.concatenate([v.confidence[v.valid] for v in views])
    keep = geo.clean_indices(world)
    cloud, cloud_rgb, cloud_conf = world[keep], rgb_all[keep], conf_all[keep]

    # planes in ARKit world (y up), then the home frame (z up, floor at 0)
    T_y = home_frame.Y_UP_TO_Z_UP
    floor, walls = geo.floor_and_walls(home_frame.apply(T_y, cloud))
    floor_z = float(np.median(floor.inliers[:, 2]))
    T = T_y.copy()
    T[2, 3] = -floor_z
    home_cloud = home_frame.apply(T, cloud)
    log.info("cloud %d points; floor found, %d walls", len(home_cloud), len(walls))
    for v in views:
        debug.frame(v, source.image_rgb(v.index))
    debug.points("cloud", home_cloud)

    # SAM 3.1 boxes on a subset of views, lifted to 3D with depth + pose
    sightings: dict[str, list[Sighting]] = defaultdict(list)
    sam_views = [v for v in views if v.index in pending] or views[:: cfg.sam_every]
    calls = 0
    for n, v in enumerate(sam_views, 1):
        jpeg = source.jpeg(v.index)
        rgb = source.image_rgb(v.index)
        h, w = v.depth.shape
        img_w, img_h = episode.image_size
        sx, sy = w / img_w, h / img_h  # SAM boxes are in source-image pixels; depth is at the output size
        futures = pending.get(v.index) or [pool.submit(sam.boxes, jpeg, c) for c in concepts]
        found = [f.result() for f in futures]  # prompt order
        for concept, boxes in zip(concepts, found, strict=True):
            calls += 1
            for b in boxes:
                if b.score < cfg.min_score:
                    continue
                box = (b.box[0] * sx, b.box[1] * sy, b.box[2] * sx, b.box[3] * sy)
                lifted = lift_box(
                    box, v.depth, v.intrinsics, v.cam2world, inner=0.9 if concept in cfg.furniture else 0.6
                )
                if lifted is None:
                    continue
                pts = home_frame.apply(T, lifted.points)
                color = dominant_color(rgb, b.box) if concept in cfg.objects else None
                sightings[concept].append(Sighting(np.median(pts, axis=0), b.score, v.index, pts, color, b.box))
        log.info("SAM view %d/%d done, %d sightings so far", n, len(sam_views), sum(map(len, sightings.values())))
    pool.shutdown()
    t_sam = time.perf_counter() - t1  # wall time from the first SAM call, which overlaps the reconstruction

    # one thing per cluster of sightings of the same label
    things = {"landmarks": [], "objects": []}
    pieces: list[Piece] = []
    n_clusters = 0
    for label, seen in sightings.items():
        centers = np.array([s.center for s in seen])
        labels = geo.clusters(centers, cfg.cluster_eps, cfg.cluster_min) if len(centers) > 1 else np.zeros(1, int)
        clusters = [[seen[i] for i in np.flatnonzero(labels == k)] for k in sorted(set(labels.tolist()) - {-1})]
        if label not in cfg.furniture:
            # a loop walk's repeat sightings of one thing, a little apart after drift, become one
            n_clusters += len(clusters)
            parts = [
                ObjectCluster(
                    np.median([m.center for m in c], axis=0),
                    vote([(m.color, m.score) for m in c]),
                    {m.frame for m in c},
                )
                for c in clusters
            ]
            clusters = [[m for i in g for m in clusters[i]] for g in merge_objects(parts, cfg.object_merge_m)]
        for members in clusters:
            pts = np.concatenate([m.points for m in members])
            lo, hi = np.percentile(pts, 5, axis=0), np.percentile(pts, 95, axis=0)
            best = max(members, key=lambda m: m.score)
            score = float(np.mean([m.score for m in members]))
            if label in cfg.furniture:
                pieces.append(Piece(label, lo, hi, score, len(members), best.frame, pts))
                continue
            things["objects"].append(
                {
                    "label": label,
                    "centroid": np.round(np.median([m.center for m in members], axis=0), 3).tolist(),
                    "bbox_min": np.round(lo, 3).tolist(),
                    "bbox_max": np.round(hi, 3).tolist(),
                    "size_m": np.round(hi - lo, 3).tolist(),
                    "confidence": round(score, 3),
                    "sightings": len(members),
                    "keyframe_index": best.frame,
                    "box": [round(float(v), 1) for v in best.box],
                    "color": vote([(m.color, m.score) for m in members]),
                }
            )

    log.info("objects: %d clusters merged into %d", n_clusters, len(things["objects"]))

    # furniture: "table" and "desk" boxes of one desk, and the parts of one big piece, become one landmark
    furniture_pts: list[tuple[str, np.ndarray]] = []
    merged = merge(pieces)
    log.info("furniture: %d boxes merged into %d", len(pieces), len(merged))
    for p, names in merged:
        centroid = np.concatenate([(p.lo[:2] + p.hi[:2]) / 2, [np.median(p.points[:, 2])]])
        things["landmarks"].append(
            {
                "label": p.label,
                "also_seen_as": names[1:],
                "centroid": np.round(centroid, 3).tolist(),
                "bbox_min": np.round(p.lo, 3).tolist(),
                "bbox_max": np.round(p.hi, 3).tolist(),
                "size_m": np.round(p.hi - p.lo, 3).tolist(),
                "confidence": round(p.confidence, 3),
                "sightings": p.sightings,
                "keyframe_index": p.keyframe_index,
                "front_dir": None,
            }
        )
        furniture_pts.append((p.label, p.points))

    floor_xy = home_frame.apply(T, home_frame.apply(np.linalg.inv(T_y), floor.inliers))  # back through T_y, then T
    wall_planes = []
    for w in walls:
        pts_home = home_frame.apply(T, home_frame.apply(np.linalg.inv(T_y), w.inliers))
        n = w.normal / np.linalg.norm(w.normal)
        d = -float(np.median(pts_home @ n))
        wall_planes.append(room_model.WallPlane(n, d, pts_home))
    room = room_model.room_json(room_model.floor_polygon(floor_xy), wall_planes, furniture_pts)
    room["north_deg"] = home_frame.north_in_home(T, episode.north_yaw_deg, episode.compass_spread_deg)

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
    if hasattr(source, "save_array"):  # the cloud for route planning, next to the episode (home frame, float16)
        source.save_array("home_cloud.npy", home_cloud.astype(np.float16))
        source.save_array("home_colors.npy", cloud_rgb.astype(np.uint8))
        source.save_array("home_conf.npy", cloud_conf.astype(np.float16))
    result = {
        "scan_id": episode.scan_id,
        "room": room,
        "landmarks": things["landmarks"],
        "objects": things["objects"],
        "transform_to_home": T.reshape(-1).round(6).tolist(),
        "provenance": {
            "segmenter": cfg.segmenter,
            "reconstructor": getattr(recon, "name", type(recon).__name__),
            "pipeline_commit": cfg.commit,
        },
        "stats": cfg.stats,
    }
    log.info(
        "%d landmarks, %d objects; total %.1f s",
        len(things["landmarks"]),
        len(things["objects"]),
        cfg.stats["total_s"],
    )
    if sink is not None:
        sink.post(episode.scan_id, result)
        log.info("results posted to the API")
    return result
