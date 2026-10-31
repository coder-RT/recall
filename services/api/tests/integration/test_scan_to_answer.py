"""The whole journey over real HTTP routing, the real SQLite store and the real disk store (no network, no models):
upload a scan → the pipeline's results → the memory answers the phone and a robot → the privacy note → erase it all.
The Guide's model and the robot screen are scripted; everything else is the real code."""

import asyncio
import hashlib
import io

import numpy as np
from a2a.helpers import get_data_parts, new_data_part, new_message
from a2a.types import Role
from fastapi.testclient import TestClient
from PIL import Image

from recall_api.application.ports import ChatReply, ToolCall
from recall_api.config.settings import Settings
from recall_api.infra.app import create_app
from tests.fakes import episode_zip
from tests.unit.test_home_memory import Screen, _send

OWNER = {"Authorization": "Bearer owner"}
ROOM = {"floor_polygon": [[0, 0], [4, 0], [4, 3], [0, 3]], "walls": [], "furniture": [], "height_m": 2.5}


def box(label, lo, hi, **more):
    c = [(a + b) / 2 for a, b in zip(lo, hi, strict=True)]
    return {"label": label, "centroid": c, "bbox_min": lo, "bbox_max": hi, "confidence": 0.9, "sightings": 3, **more}


DESK = box("desk", [0.6, 0.7, 0.0], [1.4, 1.3, 0.76])
SHELF = box("shelf", [2.7, 1.8, 0.0], [3.3, 2.2, 0.9])


def keys_at(x, y, z):
    return box("keys", [x - 0.03, y - 0.03, z - 0.01], [x + 0.03, y + 0.03, z + 0.01], color="beige",
               keyframe_index=0, box=[400.0, 300.0, 480.0, 360.0])  # fmt: skip


def result(scan_id, objects):
    return {"scan_id": scan_id, "room": ROOM, "landmarks": [DESK, SHELF], "objects": objects, "stats": {"frames": 1},
            "provenance": {"segmenter": "sam-3.1", "reconstructor": "arkit-depth", "pipeline_commit": "abc1234"},
            "transform_to_home": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]}  # fmt: skip


class Guide:
    """Muse Spark Open, scripted: asks find_object, then phrases what it returned."""

    model = "scripted"

    def chat(self, messages, tools):
        if not any(m["role"] == "tool" for m in messages):
            return ChatReply(None, [ToolCall("c1", "find_object", {"name": "keys"})])
        found = messages[-1]["content"]
        return ChatReply("Your keys are on the desk." if '"on"' in found else "Your keys are on the shelf.")


def app(tmp_path):
    s = Settings(RECALL_DATA_DIR=tmp_path, RECALL_DEVICE_KEY="owner", RECALL_ROBOT_KEY="robot",
                 RECALL_PUBLIC_URL="http://testserver", RECALL_TRACES="off", RECALL_PIPELINE_RUNNER="subprocess",
                 pipeline_command="true")  # fmt: skip
    a = create_app(s)
    c = a.state.container
    c.__dict__["llm"] = Guide()
    c.__dict__["screener"] = Screen()
    return a, TestClient(a)


def upload(http, scan_id, aligned_to=None):
    files = {"frames/000000.jpg": b"x" * 3000, "poses.jsonl": b"{}\n"}
    archive = episode_zip(files)
    sha = hashlib.sha256(archive).hexdigest()
    body = {"scan_id": scan_id, "home_id": "flat", "room": "Office",
            "archive": {"size": len(archive), "sha256": sha, "part_size": 5 * 1024 * 1024}}  # fmt: skip
    plan = http.post("/scans", json=body, headers=OWNER).json()
    assert (
        http.put(plan["parts"][0]["url"], content=archive, headers={**OWNER, "X-Content-SHA256": sha}).status_code
        == 200
    )
    manifest = {
        "scan_id": scan_id, "format": "recall-episode/1", "device": "iPhone17,1", "app_version": "0.1.0",
        "created_at": "2026-10-30T12:00:00Z", "duration_s": 30, "frame_count": 1,
        "image": {"width": 1024, "height": 768},
        "depth": {"width": 256, "height": 192, "unit": "mm", "encoding": "png16"},
        "intrinsics": {"fx": 700, "fy": 700, "cx": 512, "cy": 384}, "world_map": None, "aligned_to": aligned_to,
        "files": [{"path": p, "size": len(d), "sha256": hashlib.sha256(d).hexdigest()} for p, d in files.items()],
        "capture_metrics": {"directions_covered": 11, "keyframes_kept": 1, "keyframes_dropped_blurry": 0,
                            "tracking_normal_ratio": 1.0, "mean_speed_mps": 0.3, "peak_speed_mps": 0.5,
                            "slow_down_cues": 0, "grade": "good"},
    }  # fmt: skip
    assert http.put(plan["manifest_url"], json=manifest, headers=OWNER).status_code == 200
    assert http.post(plan["complete_url"], headers=OWNER).json()["status"] == "processing"


def pipeline_writes_the_cloud(tmp_path, scan_id):
    """What the pipeline leaves beside the episode: the room's points in the home frame (a floor and the desk)."""
    xs, ys = np.meshgrid(np.arange(0, 4, 0.05), np.arange(0, 3, 0.05))
    floor = np.stack([xs.ravel(), ys.ravel(), np.zeros(xs.size)], axis=1)
    dx, dy, dz = np.meshgrid(np.arange(0.6, 1.4, 0.05), np.arange(0.7, 1.3, 0.05), np.arange(0.1, 0.76, 0.1))
    desk = np.stack([dx.ravel(), dy.ravel(), dz.ravel()], axis=1)
    folder = next((tmp_path / "blobs" / "scans").glob(f"*_{scan_id}"))
    np.save(folder / "episode" / "home_cloud.npy", np.concatenate([floor, desk]).astype(np.float32))
    frame = io.BytesIO()
    Image.new("RGB", (1024, 768), (90, 90, 90)).save(frame, "JPEG")  # the keyframe the keys were seen in
    (folder / "episode" / "frames" / "000000.jpg").write_bytes(frame.getvalue())


S1 = "0b9f2a1e-0000-4000-8000-0000000000a1"
S2 = "0b9f2a1e-0000-4000-8000-0000000000a2"


def test_scan_answer_share_and_erase(tmp_path):
    a, http = app(tmp_path)
    upload(http, S1)
    pipeline_writes_the_cloud(tmp_path, S1)
    done = http.post(f"/scans/{S1}/results", json=result(S1, [keys_at(1.0, 1.0, 0.79)]), headers=OWNER)
    assert done.status_code == 200 and done.json()["status"] == "processed", done.text

    (keys,) = http.get("/homes/flat/objects", headers=OWNER).json()
    assert (keys["label"], keys["landmark"], keys["relation"]) == ("keys", "desk", "on")
    room = http.get("/homes/flat/room", headers=OWNER).json()
    assert room["floor_polygon"] == ROOM["floor_polygon"]
    answer = http.post("/ask", json={"home_id": "flat", "question": "Where are my keys?"}, headers=OWNER).json()
    assert (
        answer["text"] == "Your keys are on the desk."
        and answer["grounded"]
        and answer["object_id"] == keys["object_id"]
    )

    # every answer is traceable: answer → tool results → sighting → crop → scan → models
    ev = http.get(f"/answers/{answer['answer_id']}/evidence", headers=OWNER).json()
    assert ev["answer"]["question"] == "Where are my keys?" and ev["answer"]["provider"] == "baseten_spark_open"
    assert [s["kind"] for s in ev["steps"]] == ["model", "tool", "model"]
    assert ev["steps"][1]["tool"] == "find_object" and ev["steps"][1]["output"]["result"] == "found"
    (seen,) = ev["sightings"]
    assert seen["object_id"] == keys["object_id"] and seen["current"] and seen["keyframe_index"] == 0
    assert seen["scan"]["scan_id"] == S1 and seen["scan"]["room"] == "Office"
    assert seen["scan"]["provenance"]["reconstructor"] == "arkit-depth"
    crop = http.get(seen["crop_url"], headers=OWNER)
    assert crop.status_code == 200 and crop.headers["content-type"] == "image/jpeg"
    assert Image.open(io.BytesIO(crop.content)).size == (120, 90)  # the box with a quarter's margin round it
    assert http.get("/answers/nope/evidence", headers=OWNER).status_code == 404

    robot = {"Authorization": "Bearer robot"}
    assert http.get("/homes/flat/robot-export", headers=robot).status_code == 403  # off by default
    assert http.put("/sharing", json={"robot_access": True}, headers=OWNER).json()["robot_access"] is True
    assert http.get("/homes/flat/robot-export", headers=robot).status_code == 200
    msg = asyncio.run(_send(a, new_message([new_data_part({"object": "keys"})], role=Role.ROLE_USER)))
    assert get_data_parts(msg.parts)[0]["found"] is True
    privacy = http.get("/privacy", headers=OWNER).json()
    assert privacy["robot_access"] and len(privacy["sent"]) == 6

    folder = next((tmp_path / "blobs" / "scans").glob(f"*_{S1}"))
    assert http.delete(f"/scans/{S1}", headers=robot).status_code == 401  # never a robot
    assert http.delete(f"/scans/{S1}", headers=OWNER).status_code == 204
    assert http.get("/homes/flat/objects", headers=OWNER).json() == [] and not folder.exists()
    assert http.get(f"/scans/{S1}", headers=OWNER).status_code == 404
    trail = [e["action"] for e in reversed(http.get("/audit", headers=OWNER).json())]
    wanted = ["scan.ingested", "robot_access.changed", "robot_export.read", "home_memory.query", "scan.erased"]
    rest = iter(trail)
    assert all(w in rest for w in wanted), trail  # in this order, among the others (the refused export too)


def test_a_rescan_moves_the_keys_and_erasing_it_puts_them_back(tmp_path):
    _, http = app(tmp_path)
    ask = lambda: http.post("/ask", json={"home_id": "flat", "question": "Where are my keys?"}, headers=OWNER)  # noqa: E731
    upload(http, S1)
    http.post(f"/scans/{S1}/results", json=result(S1, [keys_at(1.0, 1.0, 0.79)]), headers=OWNER)
    upload(http, S2, aligned_to=S1)  # recognised in the first scan's map: the same frame
    moved = http.post(f"/scans/{S2}/results", json=result(S2, [keys_at(3.0, 2.0, 0.93)]), headers=OWNER).json()
    assert [c["kind"] for c in moved["changes"]] == ["moved"]
    assert ask().json()["text"] == "Your keys are on the shelf."
    assert http.delete(f"/scans/{S2}", headers=OWNER).status_code == 204
    (keys,) = http.get("/homes/flat/objects", headers=OWNER).json()
    assert keys["landmark"] == "desk" and not keys["stale"]
    assert ask().json()["text"] == "Your keys are on the desk."
