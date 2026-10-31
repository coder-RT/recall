"""`make demo` and `make record`: a home memory built from a recorded real scan, through the real write path.

demo:   python -m recall_api.infra.demo serve    no keys; the Guide's replies come from samples/replay/ (labelled recorded)
record: python -m recall_api.infra.demo record <result.json> --room "Living room" --captured-at <iso>
        real Muse Spark Open calls (keys from .env); writes samples/replay/flat/. Review the files before committing.
"""

from __future__ import annotations

import argparse
import json
import tempfile
from datetime import UTC, datetime
from pathlib import Path

from recall_api.adapters.outbound.replay.recorded_llm import RecordingLlm
from recall_api.application.ask_where_is import AskWhereIs
from recall_api.config.settings import REPO_ROOT, Settings
from recall_api.domain.memory import Home, Scan, ScanStatus
from recall_api.infra.container import Container
from recall_api.infra.db import API_ROOT

SAMPLE = REPO_ROOT / "samples" / "replay" / "flat"
HOME = "flat"
DEMO_KEY = "demo"  # the demo's device key: it runs on 127.0.0.1 with recorded data only
QUESTIONS = [
    "Where are my keys?", "Where did I leave my glasses?", "Where is my laptop?", "Where is my bag?",
    "Have you seen a bottle?", "Where's my book?", "Where is the laptop", "Where did I put my reading glasses?",
    "Where is my umbrella?",
]  # fmt: skip
# what a scan result may carry into the public sample: geometry, labels and colours; never paths, names or notes
OBJECT_FIELDS = ("label", "also_seen_as", "centroid", "bbox_min", "bbox_max", "size_m", "confidence", "sightings",
                 "color", "front_dir")  # fmt: skip


def sanitise(result: dict) -> dict:
    keep = lambda t: {k: t[k] for k in OBJECT_FIELDS if k in t}  # noqa: E731
    return {
        "room": result["room"],
        "landmarks": [keep(t) for t in result["landmarks"]],
        "objects": [keep(t) for t in result["objects"]],
        "transform_to_home": result.get("transform_to_home"),
    }


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
    c.scans.save(Scan(meta["scan_id"], HOME, meta["room"], ScanStatus.PROCESSING, 0, "", 0, created))
    c.ingest_scan(meta["scan_id"], json.loads((sample / "scan-result.json").read_text()))
    return c


def replay_settings(data_dir: Path, sample: Path) -> Settings:
    meta = json.loads((sample / "meta.json").read_text())
    return demo_settings(
        data_dir, LLM_PROVIDER="replay", RECALL_REPLAY_DIR=sample, RECALL_FROZEN_CLOCK=meta["recorded_at"]
    )


def serve(sample: Path, port: int) -> None:
    import uvicorn

    from recall_api.infra.app import create_app

    settings = replay_settings(Path(tempfile.mkdtemp(prefix="recall-demo-")), sample)
    build(settings, sample)
    meta = json.loads((sample / "meta.json").read_text())
    print(f"\nRecall demo: {meta['label']}\nThe Guide's replies are replayed; nothing calls a model. Try:\n")
    for q in QUESTIONS[:3]:
        body = json.dumps({"home_id": HOME, "question": q})
        print(f"  curl -s localhost:{port}/ask -H 'Authorization: Bearer {DEMO_KEY}' -H 'Content-Type: application/json' "
              f"-d '{body}'")  # fmt: skip
    print(f"\nAPI docs: http://localhost:{port}/docs (device key: {DEMO_KEY})\n")
    uvicorn.run(create_app(settings), host="127.0.0.1", port=port)


def record(result_path: Path, room: str, captured_at: str, sample: Path) -> None:
    sample.mkdir(parents=True, exist_ok=True)
    recorded_at = datetime.now(UTC).replace(microsecond=0)
    result = sanitise(json.loads(result_path.read_text()))
    (sample / "scan-result.json").write_text(json.dumps(result, indent=1) + "\n")
    meta = {
        "label": f"Recorded output of a real run on {recorded_at:%Y-%m-%d}: one living-room scan from an iPhone 16 Pro, "
        "processed by MapAnything and SAM 3.1, and Muse Spark Open's replies to the questions below.",
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
    r = sub.add_parser("record")
    r.add_argument("result", type=Path)
    r.add_argument("--room", required=True)
    r.add_argument("--captured-at", required=True)
    a = p.parse_args()
    if a.cmd == "serve":
        serve(SAMPLE, a.port)
    else:
        record(a.result, a.room, a.captured_at, SAMPLE)


if __name__ == "__main__":
    main()
