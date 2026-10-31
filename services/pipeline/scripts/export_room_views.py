"""The Photo and Architect views of an exported scan (used by export_viewer_scan.py).

Photo: the surface mesh textured with the scan's own photos (recall_pipeline.domain.texturing).
Architect: the room regenerated as a clean plan with parametric furniture (domain.architecture), and A3 drawing
sheets (domain.drawings). Everything is computed from the episode's measurements; nothing is generated. File I/O,
image decoding and OpenCV live here; the algorithms are pure and unit-tested in the pipeline's domain.
"""

from __future__ import annotations

import base64
import io
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from recall_pipeline.domain import architecture as arch
from recall_pipeline.domain import drawings, texturing
from recall_pipeline.domain.geometry import arkit_to_opencv, column_major_to_matrix

TILE = (512, 384)
CREDITS = (
    "Measured with the iPhone's LiDAR and ARKit; rebuilt by MapAnything on the Mac; furniture and things "
    "found by SAM 3.1. Drawn by Recall from measurements."
)
BANDS = ((0.3, "floor"), (0.7, "knee"), (1.1, "waist"), (1.5, "chest"), (99.0, "head"))


def cameras(ep: Path, manifest: dict, result: dict, shift: np.ndarray) -> tuple[list[texturing.Camera], list[Path]]:
    """Each keyframe as an OpenCV camera in the export's frame (home frame, x/y shifted), with its LiDAR depth."""
    T = np.array(result["transform_to_home"], dtype=float).reshape(4, 4)
    k = manifest["intrinsics"]
    K = np.array([[k["fx"], 0, k["cx"]], [0, k["fy"], k["cy"]], [0, 0, 1]])
    w, h = manifest["image"]["width"], manifest["image"]["height"]
    poses = [json.loads(line) for line in (ep / "poses.jsonl").read_text().splitlines() if line.strip()]
    cams, files, sharp = [], [], []
    for p in sorted(poses, key=lambda p: p["index"]):
        frame = ep / "frames" / f"{p['index']:06d}.jpg"
        if not frame.exists():
            continue
        c2w = T @ arkit_to_opencv(column_major_to_matrix(p["pose"]))
        c2w[:3, 3] -= shift
        depth_file = ep / "depth" / f"{p['index']:06d}.png"
        depth = np.asarray(Image.open(depth_file), dtype=np.float32) / 1000 if depth_file.exists() else None
        grey = cv2.imread(str(frame), cv2.IMREAD_GRAYSCALE)
        sharp.append(float(cv2.Laplacian(grey, cv2.CV_64F).var()))
        cams.append(texturing.Camera(K=K, cam2world=c2w, width=w, height=h, depth_m=depth))
        files.append(frame)
    med = float(np.median(sharp)) if sharp else 1.0
    cams = [
        texturing.Camera(c.K, c.cam2world, c.width, c.height, c.depth_m, float(np.clip(s / med, 0.5, 1.5)))
        for c, s in zip(cams, sharp, strict=True)
    ]
    return cams, files


def photo_view(ep: Path, out: Path, manifest: dict, result: dict, shift: np.ndarray, mesh) -> dict | None:
    pos, col, tri = mesh
    cams, files = cameras(ep, manifest, result, shift)
    if not cams:
        return None
    tm = texturing.texture(pos, tri, col, cams)
    images = [np.asarray(Image.open(files[i]).convert("RGB"), dtype=np.float32) for i in tm.frames]
    gains = texturing.exposure_gains(np.array([im.mean() for im in images]))
    cols, rows = tm.grid
    atlas = Image.new("RGB", (cols * TILE[0], rows * TILE[1]), (240, 242, 245))
    for i, (im, g) in enumerate(zip(images, gains, strict=True)):
        tile = Image.fromarray(np.clip(im * g, 0, 255).astype(np.uint8)).resize(TILE, Image.Resampling.LANCZOS)
        atlas.paste(tile, ((i % cols) * TILE[0], (i // cols) * TILE[1]))
    atlas.save(out / "photo_atlas.jpg", quality=85)
    tm.positions.astype("<f4").tofile(out / "photo_pos.bin")
    tm.uvs.astype("<f4").tofile(out / "photo_uv.bin")
    tm.index.astype("<u4").tofile(out / "photo_idx.bin")
    tm.rest_index.astype("<u4").tofile(out / "photo_rest_idx.bin")
    tm.colors.astype(np.uint8).tofile(out / "photo_col.bin")
    return {"frames_used": len(tm.frames), "textured_share": round(tm.textured_share, 3)}


def _band(z: float) -> str:
    return next(name for top, name in BANDS if z < top)


def _place(at: np.ndarray, furniture: list[drawings.Furnishing]) -> str:
    """A short spoken place for the drawings' legend: on/near the nearest furniture, and the height band."""
    near, best = None, 1.5
    for f in furniture:
        lo, hi = np.array(f.lo), np.array(f.hi)
        d = float(np.linalg.norm(np.maximum(np.maximum(lo[:2] - at[:2], 0), at[:2] - hi[:2])))
        if d < best:
            near, best = f, d
    band = f"{_band(float(at[2]))} height"
    if near is None:
        return f"in the room, {band}"
    on = best < 0.05 and abs(at[2] - near.hi[2]) < 0.15
    return f"{'on' if on else 'near'} the {near.label}, {band}"


def architect_view(
    ep: Path, out: Path, result: dict, meta: dict, points: np.ndarray, colors: np.ndarray, room_name: str
) -> tuple[dict, list[dict]]:
    """architect.json (the regenerated room in the plan frame) and the drawing sheets."""
    room = meta["room"]
    walls_home = [(tuple(w["start"]), tuple(w["end"])) for w in room["walls"]]
    theta = arch.manhattan_angle(walls_home)
    plan = arch.plan_outline(points[:, :2], theta, room["floor"])
    measured = [
        (arch.rotate(np.array(a, float), -theta), arch.rotate(np.array(b, float), -theta)) for a, b in walls_home
    ]
    walls = arch.walls_of(plan, measured)
    height = float(room.get("height_m", 2.5))

    pts_plan = np.column_stack([arch.rotate(points[:, :2], -theta), points[:, 2]])
    centre = np.array(plan.centroid.coords[0])
    furniture_json, furnishing = [], []
    for f in meta["furniture"]:
        lo_h, hi_h = np.array(f["min"]), np.array(f["max"])
        corners = arch.rotate(
            np.array([[lo_h[0], lo_h[1]], [hi_h[0], lo_h[1]], [hi_h[0], hi_h[1]], [lo_h[0], hi_h[1]]]), -theta
        )
        if f["label"] == "door":
            arch.place_door(walls, np.r_[corners.min(0), lo_h[2]], np.r_[corners.max(0), hi_h[2]])
            continue
        inside = np.all((points >= lo_h) & (points <= hi_h), axis=1)
        fit = arch.fit_box(pts_plan[inside], lo_h[2], hi_h[2])
        lo, hi = fit if fit else (np.r_[corners.min(0), lo_h[2]], np.r_[corners.max(0), hi_h[2]])
        parts = arch.furniture_parts(f["label"], lo, hi, centre)
        colour = arch.hex_colour(colors[inside], "#b9a58a")
        furniture_json.append(
            {
                "label": f["label"],
                "colour": colour,
                "lo": np.round(lo, 3).tolist(),
                "hi": np.round(hi, 3).tolist(),
                "parts": [{"kind": p.kind, "c": list(p.centre), "s": list(p.size)} for p in parts],
            }
        )
        furnishing.append(drawings.Furnishing(f["label"], tuple(np.round(lo, 3)), tuple(np.round(hi, 3))))

    floor_pts = points[:, 2] < 0.04
    wall_band = (points[:, 2] > 0.3) & (points[:, 2] < 2.0)
    items, things_json = [], []
    for n, o in enumerate(meta["objects"], start=1):
        at = np.r_[arch.rotate(np.array(o["at"][:2], float), -theta), o["at"][2]]
        title = " ".join(x for x in (o.get("color"), o["label"]) if x)
        items.append(drawings.Item(n, title, _place(at, furnishing), tuple(np.round(at, 3))))
        things_json.append(
            {
                "n": n,
                "label": o["label"],
                "color": o.get("color"),
                "at": np.round(at, 3).tolist(),
                "size": o.get("size"),
            }
        )

    model = {
        "theta": round(theta, 5),
        "height": height,
        "plan": [list(map(lambda v: round(v, 3), c)) for c in list(plan.exterior.coords)[:-1]],
        "walls": [{"a": list(w.a), "b": list(w.b), "scanned": w.scanned, "openings": w.openings} for w in walls],
        "wall_t": arch.WALL_T,
        "floor_colour": arch.hex_colour(colors[floor_pts], "#c9b79c"),
        "wall_colour": arch.hex_colour(colors[wall_band], "#eeeae4"),
        "furniture": furniture_json,
        "things": things_json,
    }
    (out / "architect.json").write_text(json.dumps(model) + "\n")

    captured = meta["stats"]["captured"]
    sheets = [
        drawings.plan_sheet(
            plan, walls, furnishing, items, room_name, captured, height, theta, CREDITS, room.get("north_deg")
        )
    ]
    seen = sorted((w for w in walls if w.scanned and w.length >= 1.0), key=lambda w: -w.length)[:4]
    if seen:
        images = []
        for w in seen:
            raster = drawings.elevation_raster(pts_plan, colors.astype(np.float32), w, height)
            buf = io.BytesIO()
            Image.fromarray(raster).save(buf, format="PNG", optimize=True)
            images.append(base64.b64encode(buf.getvalue()).decode("ascii"))
        sheets.append(drawings.elevations_sheet(seen, images, furnishing, room_name, captured, height, CREDITS))
    listed = []
    for s in sheets:
        name = f"sheet-{s.id.lower().replace('.', '-')}.svg"
        (out / name).write_text(s.svg)
        listed.append({"id": s.id, "title": s.title, "file": name, "summary": s.summary})
    return {"walls": len(walls), "scanned_walls": sum(w.scanned for w in walls)}, listed
