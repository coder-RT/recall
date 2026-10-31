"""Wiring for `recall-pipeline process`: real adapters only (MapAnything on MPS, SAM 3.1 on the Meta API, Open3D)."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from recall_pipeline.adapters.disk_source import DiskEpisodeSource
from recall_pipeline.application.process_episode import PipelineConfig, process_episode

ROOT = Path(__file__).resolve().parents[5]


def _env() -> dict[str, str]:
    env = dict(os.environ)
    p = ROOT / ".env"
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                env.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    return env


def process(episode_dir: str, scan_id: str, post: bool = True, out: str | None = None, recon=None) -> int:
    """One episode. `recon`: an already loaded reconstructor (the warm server's); otherwise MapAnything loads here."""
    from recall_pipeline.adapters.api_client import ApiResultSink
    from recall_pipeline.adapters.mapanything_local import MapAnythingLocal
    from recall_pipeline.adapters.open3d_geometry import Open3DGeometry
    from recall_pipeline.adapters.rerun_log import NoDebug, RerunDebug
    from recall_pipeline.adapters.sam31_meta_api import Sam31MetaApi
    from recall_pipeline.adapters.sam_cache import CachedSegmenter

    env = _env()
    if not env.get("META_MUSE_API_KEY"):
        print("META_MUSE_API_KEY is not set in .env: SAM 3.1 runs on the Meta Model API", file=sys.stderr)
        return 2
    sink = None
    if post:
        key = env.get("RECALL_DEVICE_KEY")
        if not key:
            print("RECALL_DEVICE_KEY is not set in .env: the pipeline can't post results", file=sys.stderr)
            return 2
        sink = ApiResultSink(env.get("RECALL_API_URL", "http://localhost:8000"), key)
    debug = RerunDebug(f"recall-{scan_id}") if env.get("RERUN") == "1" else NoDebug()
    cfg = PipelineConfig()
    sam = CachedSegmenter(Sam31MetaApi(env["META_MUSE_API_KEY"]), Path(episode_dir) / "cache" / "sam")
    result = process_episode(
        DiskEpisodeSource(episode_dir),
        recon or MapAnythingLocal(),
        sam,
        Open3DGeometry(),
        sink,
        debug,
        cfg,
    )
    result["stats"]["sam_cached"] = sam.hits
    target = Path(out) if out else Path(episode_dir) / "result.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, indent=1))
    print(json.dumps(result["stats"]))
    print(f"{len(result['landmarks'])} landmarks, {len(result['objects'])} objects -> {target}")
    return 0
