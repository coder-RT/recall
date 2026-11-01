"""Writes a robot export as files a ROS 2 robot can load: map.pgm + map.yaml (Nav2 map server), objects.json,
room.json, cloud.ply (binary, x y z only) and README.md, to a folder or as one .zip."""

from __future__ import annotations

import io
import json
import zipfile
from pathlib import Path

import numpy as np
import yaml

from recall_api.application.export_for_robot import FRAME, RobotExport


def document(e: RobotExport) -> dict:
    """objects.json: what is where, in the map frame."""
    return {
        "format": "recall-robot-export/1",
        "home_id": e.home_id,
        "room": e.room,
        "scan_id": e.scan_id,
        "frame_id": FRAME,
        "generated_at": e.generated_at.isoformat(),
        "objects": e.objects,
        "landmarks": e.landmarks,
    }


def ply(points: np.ndarray) -> bytes:
    header = (
        "ply\nformat binary_little_endian 1.0\n"
        f"comment Recall robot export: home frame, metres, z up\nelement vertex {len(points)}\n"
        "property float x\nproperty float y\nproperty float z\nend_header\n"
    )
    return header.encode() + np.asarray(points, "<f4").tobytes()


def readme(e: RobotExport) -> str:
    w, h = e.map.size
    return f"""# {e.room}: Recall robot package

From Recall's memory of this room (scan {e.scan_id}, made {e.generated_at:%Y-%m-%d %H:%M} UTC). Geometry and labels
only: no photos, no video, nothing the owner said.

All positions are in the `{FRAME}` frame: metres, the floor at z = 0, z up.

| File | What it is |
|---|---|
| `map.yaml`, `map.pgm` | 2D occupancy map for the Nav2 map server: {w} x {h} cells of {e.map.resolution} m |
| `objects.json` | {len(e.objects)} things and {len(e.landmarks)} pieces of furniture: label, colour, position, size |
| `room.json` | The room's floor outline, walls and furniture boxes |
| `cloud.ply` | {len(e.cloud)} 3D points (x y z), to plan reaching a thing at its height |

A robot with the robot key can fetch a fresh copy from the owner's Mac while robot access is on:
`GET /homes/{e.home_id}/robot-package?room={e.room}`. Recall finds things; it doesn't move them.
"""


def files(e: RobotExport) -> dict[str, bytes]:
    return {
        "README.md": readme(e).encode(),
        "map.pgm": e.map.pgm(),
        "map.yaml": yaml.safe_dump(e.map.yaml_fields("map.pgm"), sort_keys=False).encode(),
        "objects.json": (json.dumps(document(e), indent=1) + "\n").encode(),
        "room.json": (json.dumps(e.room_model, indent=1) + "\n").encode(),
        "cloud.ply": ply(e.cloud),
    }


def package(e: RobotExport) -> bytes:
    """Every file in one .zip, under a folder named after the room."""
    folder = "recall-" + "".join(ch if ch.isalnum() else "-" for ch in e.room.lower()).strip("-")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in files(e).items():
            z.writestr(f"{folder}/{name}", data)
    return buf.getvalue()


def write(e: RobotExport, folder: Path) -> list[Path]:
    folder.mkdir(parents=True, exist_ok=True)
    out = files(e)
    paths = []
    for name, data in out.items():
        (folder / name).write_bytes(data)
        paths.append(folder / name)
    return paths
