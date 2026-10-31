"""Writes a robot export as files a ROS 2 robot can load: map.pgm + map.yaml (Nav2 map server), objects.json,
room.json and cloud.ply (binary, x y z only)."""

from __future__ import annotations

import json
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


def write(e: RobotExport, folder: Path) -> list[Path]:
    folder.mkdir(parents=True, exist_ok=True)
    out = {
        "map.pgm": e.map.pgm(),
        "map.yaml": yaml.safe_dump(e.map.yaml_fields("map.pgm"), sort_keys=False).encode(),
        "objects.json": (json.dumps(document(e), indent=1) + "\n").encode(),
        "room.json": (json.dumps(e.room_model, indent=1) + "\n").encode(),
        "cloud.ply": ply(e.cloud),
    }
    paths = []
    for name, data in out.items():
        (folder / name).write_bytes(data)
        paths.append(folder / name)
    return paths
