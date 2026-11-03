"""`make demo` and `make record`: a home memory built from a recorded real scan, through the real write path.

demo:   python -m recall_api.infra.demo serve
        no keys; the Guide's replies come from samples/replay/ (labelled recorded)
walks:  python -m recall_api.infra.demo walks --viewer <meta.json> --out <walks.json>
        no keys; each recorded answer and the route to its thing, for the website's demo page
record: python -m recall_api.infra.demo record <result.json> --room "Living room" --captured-at <iso>
        real Muse Spark Open calls (keys from .env); writes samples/replay/flat/. Review the files before committing.
"""

from __future__ import annotations

import argparse
import itertools
import json
import tempfile
from datetime import UTC, datetime
from pathlib import Path

import numpy as np

from recall_api.adapters.outbound.replay.recorded_llm import RecordingLlm
from recall_api.application.ask_where_is import AskWhereIs
from recall_api.application.ingest_scan import IngestScan
from recall_api.config.settings import REPO_ROOT, Settings
from recall_api.domain.memory import Home, Scan, ScanStatus, Trust
from recall_api.infra.container import Container
from recall_api.infra.db import API_ROOT

SAMPLE = REPO_ROOT / "samples" / "replay" / "flat"
HOME = "flat"
DEMO_KEY = "demo"  # the demo's device key: it runs on 127.0.0.1 with recorded data only
QUESTIONS = [
    "Where are my keys?", "Where did I leave my glasses?", "Where is my laptop?", "Where is my wallet?",
    "Where is the remote?", "Where is my bag?", "Have you seen a bottle?", "Where's my book?",
    "Where is my umbrella?",
]  # fmt: skip
# what a scan result may carry into the public sample: geometry, labels and colours; never paths, names or notes
OBJECT_FIELDS = ("label", "also_seen_as", "centroid", "bbox_min", "bbox_max", "size_m", "confidence", "sightings",
                 "color", "front_dir")  # fmt: skip
# the scan's geometry the routes need, beside the result: the point cloud (no colours) and the path the phone walked
GEOMETRY = ("home_cloud.npy", "poses.jsonl")
VOXEL_M = 0.05  # the routes' floor grid has 10 cm cells, so one point per 5 cm loses nothing


def sanitise(result: dict) -> dict:
    keep = lambda t: {k: t[k] for k in OBJECT_FIELDS if k in t}  # noqa: E731
    return {
        "room": result["room"],
        "landmarks": [keep(t) for t in result["landmarks"]],
        "objects": [keep(t) for t in result["objects"]],
        "transform_to_home": result.get("transform_to_home"),
    }


def thin_cloud(points: np.ndarray, voxel: float = VOXEL_M) -> np.ndarray:
    """One point per `voxel` cube, positions only (no colours), as float16: small enough to publish."""
    points = np.asarray(points, dtype=np.float64)
    _, first = np.unique(np.floor(points / voxel).astype(np.int64), axis=0, return_index=True)
    return points[np.sort(first)].astype(np.float16)


def walk_poses(text: str) -> str:
    """Only the camera poses of the scan's walk (where routes start): no times, compass readings or tracking notes."""
    lines = []
    for line in text.splitlines():
        try:
            pose = json.loads(line)["pose"]
        except (ValueError, KeyError, TypeError):
            continue
        lines.append(json.dumps({"pose": [round(float(v), 5) for v in pose]}))
    return "\n".join(lines) + "\n"


def demo_settings(data_dir: Path, **more) -> Settings:
    return Settings(
        RECALL_DATA_DIR=data_dir,
        RECALL_DATABASE_URL=f"sqlite:///{data_dir / 'demo.db'}",
        RECALL_DEVICE_KEY=DEMO_KEY,
        RECALL_TRACES="off",
        RECALL_PIPELINE_RUNNER="subprocess",
        RECALL_HOME_ID=HOME,
        **more,
    )


def build(settings: Settings, sample: Path) -> Container:
    """A fresh memory from the sample scan: the scan is ingested exactly as the pipeline's result would be."""
    meta = json.loads((sample / "meta.json").read_text())
    c = Container(settings)
    c.homes.save(Home(id=HOME, name=HOME))
    created = datetime.fromisoformat(meta["captured_at"])
    scan = Scan(meta["scan_id"], HOME, meta["room"], ScanStatus.PROCESSING, 0, "", 0, created)
    c.scans.save(scan)
    # the same ids every time, so a recorded tool call that names an object finds it again in the replay
    n = itertools.count(1)
    ingest = IngestScan(c.scans, c.homes, c.objects, c.clock, lambda prefix: f"{prefix}_demo{next(n)}", audit=c.auditor)
    ingest(meta["scan_id"], json.loads((sample / "scan-result.json").read_text()))
    # the geometry goes where a processed scan keeps it, so routes are planned by the same code as for a live scan
    for name in GEOMETRY:
        if (sample / name).exists():
            c.blobs.put(f"{scan.folder}/episode/{name}", (sample / name).read_bytes())
    # the Guide's replies were recorded when every find counted (both bags were seen in one photo each), so the
    # replayed memory uses the same level, or the recordings would no longer be what it says
    c.owner_settings.put("trust", Trust.EVERYTHING.value)
    return c


def replay_settings(data_dir: Path, sample: Path) -> Settings:
    meta = json.loads((sample / "meta.json").read_text())
    return demo_settings(
        data_dir, LLM_PROVIDER="replay", RECALL_REPLAY_DIR=sample, RECALL_FROZEN_CLOCK=meta["recorded_at"]
    )


def viewer_shift(objects: list[dict], viewer_objects: list[dict]) -> np.ndarray:
    """The viewer export centres the room on x/y; the shift is found from the things both list (same scan), and
    checked: every matched thing must land within 2 cm, or the viewer shows a different scan."""
    ours = [o for o in objects if sum(p["label"] == o["label"] for p in objects) == 1]
    pairs = []
    for o in ours:
        same = [v for v in viewer_objects if v["label"] == o["label"]]
        if len(same) == 1:
            pairs.append((np.array(o["centroid"][:2]), np.array(same[0]["at"][:2])))
    if len(pairs) < 3:
        raise ValueError("The viewer export and the sample share too few things: are they the same scan?")
    shift = np.median([a - b for a, b in pairs], axis=0)
    worst = max(float(np.linalg.norm(a - b - shift)) for a, b in pairs)
    if worst > 0.02:
        raise ValueError(f"The viewer export is not this scan (things differ by up to {worst:.2f} m).")
    return shift


def walks(sample: Path, viewer_meta: Path) -> dict:
    """Each recorded question, answered by the replayed Guide, and the route the phone would give from where the scan
    began: the same A* on the scan's floor and the same clock-face steps. Positions are in the viewer's frame."""
    meta = json.loads((sample / "meta.json").read_text())
    c = build(replay_settings(Path(tempfile.mkdtemp(prefix="recall-walks-")), sample), sample)
    result = json.loads((sample / "scan-result.json").read_text())
    shift = viewer_shift(result["objects"], json.loads(viewer_meta.read_text())["objects"])
    xy = lambda p: [round(float(p[0] - shift[0]), 3), round(float(p[1] - shift[1]), 3)]  # noqa: E731
    first = json.loads((sample / "poses.jsonl").read_text().splitlines()[0])["pose"]
    items = []
    for rec in meta["answers"]:
        a = c.ask(HOME, rec["question"])
        item: dict = {"question": rec["question"], "answer": a.text, "grounded": a.grounded, "model": a.model}
        obj = c.objects.get(a.object_id) if a.object_id else None
        seen = obj.where(Trust.EVERYTHING) if obj else None
        alike = [o for o in c.objects.list_for_home(HOME) if obj and o.label == obj.label and o.where(Trust.EVERYTHING)]
        if len(alike) > 1:
            item["asks_which"] = True  # several alike: the answer asks which one, so no route until the person says
        elif seen:
            g = c.guidance.start(HOME, obj.id, first, "normal")
            item |= {
                "label": obj.label,
                "target": [*xy((seen.position.x, seen.position.y)), round(seen.position.z, 3)],
                "mode": g["mode"],
                "steps": [{k: s[k] for k in ("clock", "metres", "say")} for s in g["steps"]],
                "arrive": g["arrive_say"],
                "path": [xy(p) for p in g["path"]],
            }
        items.append(item)
    return {
        "label": meta["label"],
        "recorded_at": meta["recorded_at"],
        "captured_at": meta["captured_at"],
        "room": meta["room"],
        "frame": "the viewer's: home frame (floor z = 0, z up, metres), x/y centred on the room as in meta.json",
        "walks": items,
    }


def serve(sample: Path, port: int) -> None:
    import uvicorn

    from recall_api.infra.app import create_app

    settings = replay_settings(Path(tempfile.mkdtemp(prefix="recall-demo-")), sample)
    build(settings, sample)
    meta = json.loads((sample / "meta.json").read_text())
    print(f"\nRecall demo: {meta['label']}\nThe Guide's replies are replayed; nothing calls a model. Try:\n")
    for q in QUESTIONS[:3]:
        body = json.dumps({"home_id": HOME, "question": q})
        auth = f"-H 'Authorization: Bearer {DEMO_KEY}' -H 'Content-Type: application/json'"
        print(f"  curl -s localhost:{port}/ask {auth} -d '{body}'")
    print(f"\nAPI docs: http://localhost:{port}/docs (device key: {DEMO_KEY})")
    print("Ask, then walk (the website's demo page, started by make demo): http://localhost:3000/demo\n")
    uvicorn.run(create_app(settings), host="127.0.0.1", port=port)


def record(result_path: Path, room: str, captured_at: str, sample: Path) -> None:
    sample.mkdir(parents=True, exist_ok=True)
    recorded_at = datetime.now(UTC).replace(microsecond=0)
    result = sanitise(json.loads(result_path.read_text()))
    (sample / "scan-result.json").write_text(json.dumps(result, indent=1) + "\n")
    episode = result_path.parent
    if (episode / "home_cloud.npy").exists():
        np.save(sample / "home_cloud.npy", thin_cloud(np.load(episode / "home_cloud.npy")))
    if (episode / "poses.jsonl").exists():
        (sample / "poses.jsonl").write_text(walk_poses((episode / "poses.jsonl").read_text()))
    meta = {
        "label": f"Recorded output of a real run on {recorded_at:%Y-%m-%d}: one living-room scan from an iPhone "
        "16 Pro, processed by MapAnything and SAM 3.1, and Muse Spark Open's replies to the questions below.",
        "scan_id": "demo-living-room",
        "room": room,
        "captured_at": captured_at,
        "recorded_at": recorded_at.isoformat(),
    }
    (sample / "meta.json").write_text(json.dumps(meta, indent=1) + "\n")
    settings = demo_settings(Path(tempfile.mkdtemp(prefix="recall-record-")), RECALL_FROZEN_CLOCK=recorded_at)
    c = build(settings, sample)
    recording = RecordingLlm(c.llm)
    schemas = json.loads((API_ROOT / "resources" / "tools.json").read_text())
    guide = AskWhereIs(recording, c.tools, schemas, c.homes)
    answers = []
    for q in QUESTIONS:
        a = guide(HOME, q)
        answers.append({"question": q, "answer": a.text, "tool_calls": a.tool_calls, "model": a.model})
        print(f"{a.latency_ms:>6} ms  {q} -> {a.text}")
    meta["answers"] = answers
    (sample / "meta.json").write_text(json.dumps(meta, indent=1) + "\n")
    (sample / "guide.jsonl").write_text("".join(json.dumps(line) + "\n" for line in recording.lines))
    print(f"\nWrote {sample}. Review every file before committing (nothing personal, CLAUDE.md #19).")


def main() -> None:
    p = argparse.ArgumentParser(prog="recall-demo")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("serve")
    s.add_argument("--port", type=int, default=8000)
    w = sub.add_parser("walks")
    w.add_argument("--viewer", type=Path, required=True, help="the website's meta.json for the same scan")
    w.add_argument("--out", type=Path, required=True)
    r = sub.add_parser("record")
    r.add_argument("result", type=Path)
    r.add_argument("--room", required=True)
    r.add_argument("--captured-at", required=True)
    a = p.parse_args()
    if a.cmd == "serve":
        serve(SAMPLE, a.port)
    elif a.cmd == "walks":
        a.out.write_text(json.dumps(walks(SAMPLE, a.viewer), indent=1) + "\n")
        print(f"Wrote {a.out}")
    else:
        record(a.result, a.room, a.captured_at, SAMPLE)


if __name__ == "__main__":
    main()
