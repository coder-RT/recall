"""The whole pipeline on a synthetic room, no models and no network: a real episode folder (manifest, JPEG frames,
16-bit LiDAR depth, confidence, ARKit poses) is ray-cast from a known room, then process_episode runs with the
no-model reconstructor (LiDAR depth + ARKit poses), a stand-in for SAM 3.1 that reports the true boxes, and the real
Open3D geometry. What comes out must match the room we built: floor at 0, the walls, the table, the keys."""

from __future__ import annotations

import io
import json
from pathlib import Path

import cv2
import numpy as np
import pytest
import yaml
from PIL import Image

from recall_pipeline.adapters.arkit_depth import ArkitDepth
from recall_pipeline.adapters.disk_source import DiskEpisodeSource
from recall_pipeline.adapters.open3d_geometry import Open3DGeometry
from recall_pipeline.adapters.rerun_log import NoDebug
from recall_pipeline.application.ports import Box
from recall_pipeline.application.process_episode import PipelineConfig, process_episode
from recall_pipeline.domain.geometry import arkit_to_opencv

# the room in ARKit's world (y up, metres): floor y = 0, walls at x = ±2 and z = ±1.5, ceiling 2.5
ROOM_MIN, ROOM_MAX = np.array([-2.0, 0.0, -1.5]), np.array([2.0, 2.5, 1.5])
TABLE = (np.array([0.2, 0.0, -1.0]), np.array([1.0, 0.75, -0.4]))
KEYS = (np.array([0.56, 0.75, -0.73]), np.array([0.64, 0.78, -0.67]))
W, H, F = 320, 240, 250.0
SHADE = {0: (120, 120, 120), 1: (200, 190, 170), 2: (110, 70, 40), 3: (230, 200, 40)}  # floor, wall, table, keys


def pose(yaw_deg: float, pitch_deg: float, at) -> np.ndarray:
    """ARKit camera-to-world: the camera looks along its −Z, up is +Y."""
    y, p = np.radians(yaw_deg), np.radians(pitch_deg)
    Ry = np.array([[np.cos(y), 0, np.sin(y)], [0, 1, 0], [-np.sin(y), 0, np.cos(y)]])
    Rx = np.array([[1, 0, 0], [0, np.cos(p), -np.sin(p)], [0, np.sin(p), np.cos(p)]])
    T = np.eye(4)
    T[:3, :3], T[:3, 3] = Ry @ Rx, at
    return T


def slab(o, d, lo, hi):
    """Ray/box entry distance (inf when missed)."""
    with np.errstate(divide="ignore", invalid="ignore"):
        t1, t2 = (lo - o) / d, (hi - o) / d
    tmin = np.nanmax(np.minimum(t1, t2), axis=-1)
    tmax = np.nanmin(np.maximum(t1, t2), axis=-1)
    return np.where((tmax >= tmin) & (tmin > 0), tmin, np.inf)


def render(T_arkit: np.ndarray):
    """Depth along the camera's view axis (metres) and which surface each pixel sees."""
    cv = arkit_to_opencv(T_arkit)
    u, v = np.meshgrid(np.arange(W) + 0.5, np.arange(H) + 0.5)
    cam = np.stack([(u - W / 2) / F, (v - H / 2) / F, np.ones_like(u)], axis=-1)  # z = 1: t is the z-depth
    d = cam @ cv[:3, :3].T
    o = cv[:3, 3]
    with np.errstate(divide="ignore", invalid="ignore"):
        t_in = np.where(d > 0, (ROOM_MAX - o) / d, (ROOM_MIN - o) / d)  # leaving the room through the far face
    t_room = np.nanmin(np.where(t_in > 0, t_in, np.inf), axis=-1)
    hit_axis = np.nanargmin(np.where(t_in > 0, t_in, np.inf), axis=-1)
    surface = np.where((hit_axis == 1) & (d[..., 1] < 0), 0, 1)  # the floor, else a wall (or the ceiling)
    t = t_room
    for sid, (lo, hi) in ((2, TABLE), (3, KEYS)):
        tb = slab(o, d, lo, hi)
        closer = tb < t
        t, surface = np.where(closer, tb, t), np.where(closer, sid, surface)
    return t, surface


def write_episode(folder: Path, n: int = 12) -> list[np.ndarray]:
    rng = np.random.default_rng(0)
    for sub in ("frames", "depth", "confidence"):
        (folder / sub).mkdir(parents=True)
    poses, lines = [], []
    for i in range(n):
        # a slow walk round the room's middle, looking a little down, turning a full circle
        T = pose(i * 360 / n, -25, [0.3 * np.cos(i), 1.4, 0.3 * np.sin(i)])
        depth, surface = render(T)
        rgb = np.zeros((H, W, 3), np.uint8)
        for sid, colour in SHADE.items():
            rgb[surface == sid] = colour
        rgb = np.clip(rgb + rng.normal(0, 12, rgb.shape), 0, 255).astype(np.uint8)  # texture, so nothing reads as blur
        buf = io.BytesIO()
        Image.fromarray(rgb).save(buf, "JPEG", quality=92)
        (folder / "frames" / f"{i:06d}.jpg").write_bytes(buf.getvalue())
        mm = np.clip(np.nan_to_num(depth * 1000, posinf=0), 0, 65535).astype(np.uint16)
        cv2.imwrite(str(folder / "depth" / f"{i:06d}.png"), mm)
        cv2.imwrite(str(folder / "confidence" / f"{i:06d}.png"), np.full((H, W), 2, np.uint8))
        poses.append(T)
        lines.append({"index": i, "t": i * 0.5, "pose": T.ravel(order="F").tolist(), "tracking": "normal"})
    (folder / "poses.jsonl").write_text("".join(json.dumps(x) + "\n" for x in lines))
    manifest = {"format": "recall-episode/1", "scan_id": "synthetic", "frame_count": n,
                "image": {"width": W, "height": H}, "depth": {"width": W, "height": H, "unit": "mm"},
                "intrinsics": {"fx": F, "fy": F, "cx": W / 2, "cy": H / 2}, "world_map": None}  # fmt: skip
    (folder / "manifest.json").write_text(json.dumps(manifest))
    return poses


class TrueBoxes:
    """Stands in for SAM 3.1: the true table and keys boxes, projected into each frame it is shown."""

    def __init__(self, folder: Path, poses: list[np.ndarray]) -> None:
        self.by_jpeg = {(folder / "frames" / f"{i:06d}.jpg").read_bytes(): T for i, T in enumerate(poses)}

    def boxes(self, jpeg: bytes, concept: str) -> list[Box]:
        target = {"table": TABLE, "keys": KEYS}.get(concept)
        if target is None:
            return []
        cv = arkit_to_opencv(self.by_jpeg[jpeg])
        lo, hi = target
        corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
        cam = (corners - cv[:3, 3]) @ cv[:3, :3]
        if (cam[:, 2] <= 0.1).any():
            return []
        u, v = F * cam[:, 0] / cam[:, 2] + W / 2, F * cam[:, 1] / cam[:, 2] + H / 2
        x1, y1, x2, y2 = max(u.min(), 0), max(v.min(), 0), min(u.max(), W - 1), min(v.max(), H - 1)
        if x2 - x1 < 4 or y2 - y1 < 4:
            return []  # out of the frame
        return [Box(concept, 0.9, (float(x1), float(y1), float(x2), float(y2)))]  # SAM boxes what it sees


class Sink:
    def __init__(self) -> None:
        self.posted: list[tuple[str, dict]] = []

    def post(self, scan_id: str, result: dict) -> None:
        self.posted.append((scan_id, result))


@pytest.fixture(scope="module")
def run(tmp_path_factory):
    folder = tmp_path_factory.mktemp("episode")
    poses = write_episode(folder)
    sink = Sink()
    cfg = PipelineConfig(sam_every=1, sam_workers=2)
    result = process_episode(DiskEpisodeSource(folder), ArkitDepth(), TrueBoxes(folder, poses), Open3DGeometry(),
                             sink, NoDebug(), cfg)  # fmt: skip
    T = np.array(result["transform_to_home"], dtype=float).reshape(4, 4)
    return result, sink, T, folder


def home(T, p):
    return (T @ np.append(p, 1.0))[:3]


def test_it_posts_what_the_api_accepts(run):
    result, sink, _, folder = run
    assert sink.posted and sink.posted[0][1] is result
    schemas = Path(__file__).resolve().parents[3] / "api" / "resources" / "schemas"
    required = yaml.safe_load((schemas / "ScanResult.yaml").read_text())["required"]
    thing = yaml.safe_load((schemas / "DetectedThing.yaml").read_text())["required"]
    assert set(required) <= set(result)
    for t in result["landmarks"] + result["objects"]:
        assert set(thing) <= set(t)
    assert (folder / "home_cloud.npy").exists()  # what the API's robot export reads


def test_the_floor_is_at_zero_and_the_walls_where_we_built_them(run):
    result, _, T, _ = run
    assert abs(home(T, [0.0, 0.0, 0.0])[2]) < 0.02
    lines = {("x", -2.0), ("x", 2.0), ("z", -1.5), ("z", 1.5)}
    near = set()
    for w in result["room"]["walls"]:
        for axis, value in lines:
            k = 0 if axis == "x" else 2
            ends = []
            for end in (w["start"], w["end"]):
                # back from home xy to ARKit: invert T on a floor-level point
                p = np.linalg.inv(T) @ np.array([end[0], end[1], 0.0, 1.0])
                ends.append(abs(p[k] - value))
            if max(ends) < 0.10:
                near.add((axis, value))
    assert len(near) >= 2, result["room"]["walls"]


def test_the_table_and_the_keys_are_found_where_they_are(run):
    result, _, T, _ = run
    # the best-supported table; a box cut by the frame's edge can also lift a one-sighting "table" onto the floor
    table = max((t for t in result["landmarks"] if t["label"] == "table"), key=lambda t: t["sightings"])
    assert table["sightings"] >= 3
    (keys,) = [t for t in result["objects"] if t["label"] == "keys"]
    true_keys = home(T, (KEYS[0] + KEYS[1]) / 2)
    assert np.linalg.norm(np.array(keys["centroid"]) - true_keys) < 0.05, (keys["centroid"], true_keys)
    true_top = home(T, [0.6, 0.75, -0.7])[2]
    assert abs(table["bbox_max"][2] - true_top) < 0.08
    true_table = home(T, (TABLE[0] + TABLE[1]) / 2)
    assert np.linalg.norm(np.array(table["centroid"])[:2] - true_table[:2]) < 0.10
    assert keys["color"] == "yellow"
