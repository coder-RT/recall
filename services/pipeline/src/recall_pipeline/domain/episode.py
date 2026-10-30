"""An episode as the phone recorded it (see services/api/resources/schemas/Manifest.yaml and PoseRecord.yaml)."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .geometry import column_major_to_matrix

FORMAT = "recall-episode/1"


@dataclass(frozen=True)
class Intrinsics:
    fx: float
    fy: float
    cx: float
    cy: float

    def matrix(self) -> np.ndarray:
        return np.array([[self.fx, 0, self.cx], [0, self.fy, self.cy], [0, 0, 1]], dtype=np.float64)


@dataclass(frozen=True)
class FrameRecord:
    index: int
    t: float
    pose_arkit: np.ndarray  # 4x4 camera-to-world, ARKit camera convention
    tracking: str
    reason: str | None


@dataclass(frozen=True)
class Episode:
    scan_id: str
    image_size: tuple[int, int]
    depth_size: tuple[int, int]
    intrinsics: Intrinsics
    frames: tuple[FrameRecord, ...]
    world_map: str | None

    @staticmethod
    def from_records(manifest: dict, pose_lines: list[dict]) -> Episode:
        if manifest.get("format") != FORMAT:
            raise ValueError(f"unknown episode format {manifest.get('format')!r}")
        if manifest["depth"]["unit"] != "mm":
            raise ValueError("depth must be in millimetres")
        frames = tuple(
            FrameRecord(
                int(p["index"]), float(p["t"]), column_major_to_matrix(p["pose"]), p["tracking"], p.get("reason")
            )
            for p in sorted(pose_lines, key=lambda p: p["index"])
        )
        if len(frames) != manifest["frame_count"]:
            raise ValueError(f"manifest says {manifest['frame_count']} frames, poses.jsonl has {len(frames)}")
        i = manifest["intrinsics"]
        return Episode(
            scan_id=manifest["scan_id"],
            image_size=(manifest["image"]["width"], manifest["image"]["height"]),
            depth_size=(manifest["depth"]["width"], manifest["depth"]["height"]),
            intrinsics=Intrinsics(i["fx"], i["fy"], i["cx"], i["cy"]),
            frames=frames,
            world_map=manifest.get("world_map"),
        )
