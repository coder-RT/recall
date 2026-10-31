"""Export a processed scan for the web viewer: the cloud, the room model and what Recall found.

Input: an episode folder the pipeline has processed (home_cloud.npy, home_colors.npy, home_conf.npy, result.json,
manifest.json). Output, in the home frame (floor z = 0, z up, metres) shifted so the room is centred on x/y:
points.bin (float32 xyz), colors.bin (uint8 rgb), conf.bin (uint8, rank within the room), and meta.json with
bounds, horizontal surfaces, the room model (floor outline, walls, furniture), the objects and the run's stats.
With --mesh (default on) it also writes the room as a coloured surface: Poisson reconstruction over the measured
points (Open3D, classic geometry; nothing is generated), trimmed to where the scan had points: mesh_pos.bin
(float32 xyz), mesh_col.bin (uint8 rgb), mesh_idx.bin (uint32 triangles).
Then the Photo view (that mesh textured with the scan's own photos: photo_*.bin, photo_atlas.jpg) and the Architect
view (the room regenerated as a clean plan with parametric furniture: architect.json, and A3 drawing sheets
sheet-a1-1.svg, sheet-a2-1.svg); see export_room_views.py.

    uv run --project services/pipeline python services/pipeline/scripts/export_viewer_scan.py EPISODE OUT_DIR
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from export_room_views import architect_view, photo_view
from export_viewer_points import find_surfaces, voxel_downsample


def _xy(p, shift):
    return [round(p[0] - shift[0], 3), round(p[1] - shift[1], 3)]


def _xyz(p, shift):
    return [round(p[0] - shift[0], 3), round(p[1] - shift[1], 3), round(p[2], 3)]


def surface_mesh(points: np.ndarray, colors: np.ndarray, triangles: int):
    """The measured points as a coloured surface: normals oriented towards where the camera stood (above the
    floor, inside the room), screened Poisson, then every vertex Poisson invented far from a real point is cut
    (low support density), so holes stay holes instead of being filled with guesses."""
    import open3d as o3d

    pcd = o3d.geometry.PointCloud(o3d.utility.Vector3dVector(points))
    pcd.colors = o3d.utility.Vector3dVector(colors.astype(np.float64) / 255)
    pcd = pcd.voxel_down_sample(0.02)
    if len(pcd.points) < 1000:
        return None
    pcd.estimate_normals(o3d.geometry.KDTreeSearchParamHybrid(radius=0.08, max_nn=30))
    centre = np.asarray(pcd.points).mean(0)
    pcd.orient_normals_towards_camera_location(np.array([centre[0], centre[1], 1.4]))
    # one thread: the multithreaded solver aborts ("Failed to close loop") on real scans with Open3D 0.19
    mesh, density = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(pcd, depth=9, n_threads=1)
    density = np.asarray(density)
    mesh.remove_vertices_by_mask(density < np.quantile(density, 0.08))
    # nothing beyond the measured points' extent (Poisson closes the volume)
    lo, hi = np.asarray(pcd.points).min(0) - 0.02, np.asarray(pcd.points).max(0) + 0.02
    mesh = mesh.crop(o3d.geometry.AxisAlignedBoundingBox(lo, hi))
    if len(mesh.triangles) > triangles:
        mesh = mesh.simplify_quadric_decimation(triangles)
    mesh.remove_unreferenced_vertices()
    pos = np.asarray(mesh.vertices)
    col = (np.clip(np.asarray(mesh.vertex_colors), 0, 1) * 255).round()
    return pos, col, np.asarray(mesh.triangles)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("episode", type=Path)
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--target", type=int, default=150_000, help="approximate number of points to keep")
    ap.add_argument("--no-mesh", dest="mesh", action="store_false", help="skip the surface mesh")
    ap.add_argument("--triangles", type=int, default=120_000, help="triangle budget for the surface mesh")
    ap.add_argument("--no-photo", dest="photo", action="store_false", help="skip the photo-textured view")
    ap.add_argument("--no-architect", dest="architect", action="store_false", help="skip the architect view and sheets")
    args = ap.parse_args()

    ep = args.episode
    points = np.load(ep / "home_cloud.npy").astype(np.float64)
    colors = np.load(ep / "home_colors.npy")
    conf = np.load(ep / "home_conf.npy").astype(np.float32)
    result = json.loads((ep / "result.json").read_text())
    manifest = json.loads((ep / "manifest.json").read_text())

    # stray points far outside the room go; then centre the room on x/y (everything below shifts the same)
    lo, hi = np.percentile(points, 0.5, axis=0), np.percentile(points, 99.5, axis=0)
    inside = np.all((points >= lo) & (points <= hi), axis=1) & (points[:, 2] > -0.05)
    points, colors, conf = points[inside], colors[inside], conf[inside]
    shift = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, 0.0])
    points = points - shift

    voxel = 0.015
    idx = voxel_downsample(points, voxel)
    while len(idx) > args.target:
        voxel *= 1.15
        idx = voxel_downsample(points, voxel)
    kept = points[idx]
    rank = np.argsort(np.argsort(conf[idx]))  # confidence by rank within this room (raw values are unbounded)
    conf_u8 = (rank / max(len(rank) - 1, 1) * 255).astype(np.uint8)

    room = result["room"]
    meta = {
        "count": int(len(kept)),
        "voxel_m": round(voxel, 4),
        "frame": "home: floor z = 0, z up, metres; x/y centred on the room",
        "bounds": {"min": np.round(kept.min(0), 3).tolist(), "max": np.round(kept.max(0), 3).tolist()},
        "surfaces": find_surfaces(points[voxel_downsample(points, 0.02)]),
        "room": {
            "floor": [_xy(p, shift) for p in room["floor_polygon"]],
            "walls": [
                {"start": _xy(w["start"], shift), "end": _xy(w["end"], shift), "height_m": round(w["height_m"], 2)}
                for w in room["walls"]
            ],
            "height_m": round(room["height_m"], 2),
            "north_deg": room.get("north_deg"),
        },
        "furniture": [
            {
                "label": t["label"],
                "min": _xyz(t["bbox_min"], shift),
                "max": _xyz(t["bbox_max"], shift),
                "confidence": t["confidence"],
            }
            for t in result["landmarks"]
        ],
        "objects": [
            {
                "label": t["label"],
                "color": t.get("color"),
                "at": _xyz(t["centroid"], shift),
                "size": [round(v, 3) for v in t["size_m"]] if t.get("size_m") else None,
                "confidence": t["confidence"],
            }
            for t in sorted(result["objects"], key=lambda t: -t["confidence"])
        ],
        "stats": {
            "source": "one room, iPhone 16 Pro scan with ARKit poses and LiDAR depth; MapAnything (map-anything-apache)"
            " on the Mac's GPU, SAM 3.1 on the Meta Model API",
            "frames": manifest["frame_count"],
            "duration_s": round(manifest["duration_s"]),
            "reconstruct_s": result["stats"]["reconstruct_s"],
            "sam_calls": result["stats"]["sam_calls"],
            "total_s": result["stats"]["total_s"],
            "captured": manifest["created_at"][:10],
        },
    }
    args.out_dir.mkdir(parents=True, exist_ok=True)
    if args.mesh:
        mesh = surface_mesh(points, colors, args.triangles)
        if mesh is not None:
            pos, col, tri = mesh
            pos.astype("<f4").tofile(args.out_dir / "mesh_pos.bin")
            col.astype(np.uint8).tofile(args.out_dir / "mesh_col.bin")
            tri.astype("<u4").tofile(args.out_dir / "mesh_idx.bin")
            meta["mesh"] = {"vertices": int(len(pos)), "triangles": int(len(tri))}
            if args.photo:
                photo = photo_view(ep, args.out_dir, manifest, result, shift, mesh)
                if photo:
                    meta["photo"] = photo
    if args.architect:
        # the room's name is in the scan folder's name: scans/<time>_<room-slug>_<id>/episode
        slug = ep.resolve().parent.name.split("_")[1] if "_" in ep.resolve().parent.name else "room"
        room_name = slug.replace("-", " ").capitalize()
        meta["architect"], meta["drawings"] = architect_view(ep, args.out_dir, result, meta, points, colors, room_name)
    kept.astype("<f4").tofile(args.out_dir / "points.bin")
    colors[idx].astype(np.uint8).tofile(args.out_dir / "colors.bin")
    conf_u8.tofile(args.out_dir / "conf.bin")
    (args.out_dir / "meta.json").write_text(json.dumps(meta, indent=1) + "\n")
    print(
        f"{len(kept)} points (voxel {voxel:.3f} m), {len(meta['furniture'])} furniture, {len(meta['objects'])} objects,"
        f" {len(meta['surfaces'])} surfaces, photo {meta.get('photo')}, architect {meta.get('architect')},"
        f" {len(meta.get('drawings', []))} sheets -> {args.out_dir}"
    )


if __name__ == "__main__":
    main()
