"""The upload over real HTTP routing, the real SQLite store and the real disk store (no network)."""

import hashlib

from fastapi.testclient import TestClient

from recall_api.config.settings import Settings
from recall_api.infra.app import create_app
from tests.fakes import episode_zip

SCAN = "0b9f2a1e-0000-4000-8000-000000000002"
AUTH = {"Authorization": "Bearer test-key"}


def test_upload_parts_manifest_and_complete(tmp_path, monkeypatch):
    s = Settings(
        RECALL_DATA_DIR=tmp_path,
        RECALL_DEVICE_KEY="test-key",
        pipeline_command="true",
        RECALL_TRACES="off",
        RECALL_PIPELINE_RUNNER="subprocess",
    )
    client = TestClient(create_app(s))
    files = {"frames/000000.jpg": b"x" * 3000, "poses.jsonl": b"{}\n"}
    archive = episode_zip(files)
    body = {
        "scan_id": SCAN,
        "home_id": "flat",
        "room": "Living room",
        "archive": {"size": len(archive), "sha256": hashlib.sha256(archive).hexdigest(), "part_size": 5 * 1024 * 1024},
    }
    assert client.post("/scans", json=body).status_code == 401
    plan = client.post("/scans", json=body, headers=AUTH).json()
    assert [p["received"] for p in plan["parts"]] == [False]
    r = client.put(
        plan["parts"][0]["url"],
        content=archive,
        headers={**AUTH, "X-Content-SHA256": hashlib.sha256(archive).hexdigest()},
    )
    assert r.status_code == 200, r.text
    manifest = {
        "scan_id": SCAN,
        "format": "recall-episode/1",
        "device": "iPhone17,1",
        "app_version": "0.1.0",
        "created_at": "2026-10-30T12:00:00Z",
        "duration_s": 30,
        "frame_count": 1,
        "image": {"width": 1024, "height": 768},
        "depth": {"width": 256, "height": 192, "unit": "mm", "encoding": "png16"},
        "intrinsics": {"fx": 700, "fy": 700, "cx": 512, "cy": 384},
        "world_map": None,
        "files": [{"path": p, "size": len(d), "sha256": hashlib.sha256(d).hexdigest()} for p, d in files.items()],
        "capture_metrics": {
            "directions_covered": 11,
            "keyframes_kept": 1,
            "keyframes_dropped_blurry": 0,
            "tracking_normal_ratio": 1.0,
            "mean_speed_mps": 0.3,
            "peak_speed_mps": 0.5,
            "slow_down_cues": 0,
            "grade": "good",
        },
    }
    assert client.put(plan["manifest_url"], json=manifest, headers=AUTH).status_code == 200
    done = client.post(plan["complete_url"], headers=AUTH).json()
    assert done["status"] == "processing", done
    (folder,) = (tmp_path / "blobs" / "scans").glob(f"*_{SCAN}")  # time and room first, the id last
    assert (folder / "episode" / "frames" / "000000.jpg").read_bytes() == files["frames/000000.jpg"]
