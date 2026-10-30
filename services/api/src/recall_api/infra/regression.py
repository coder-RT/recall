"""Stored scans as regression tests: re-run the pipeline on each processed scan without posting, and compare the
objects with the previous run. Writes data/regression/<scan folder>/<date>.json and appends to report.md."""

from __future__ import annotations

import json
import logging
import math
from collections.abc import Callable
from datetime import UTC, datetime

from sqlalchemy import text

from recall_api.config.settings import Settings

log = logging.getLogger("recall_api.regression")
MOVED_M = 0.2  # an object whose position changed more than this between runs is reported


def compare(before: dict, after: dict) -> dict:
    """Per label, the nearest object in the new run for each one in the old run."""
    out = {"same": 0, "shifted": [], "missing": [], "new": 0}
    old, new = before.get("objects", []), list(after.get("objects", []))
    for o in old:
        same = [n for n in new if n["label"] == o["label"]]
        if not same:
            out["missing"].append(o["label"])
            continue
        best = min(same, key=lambda n: math.dist(n["centroid"], o["centroid"]))
        d = math.dist(best["centroid"], o["centroid"])
        new.remove(best)
        if d > MOVED_M:
            out["shifted"].append(f"{o['label']} {d:.2f} m")
        else:
            out["same"] += 1
    out["new"] = len(new)
    return out


def run(settings: Settings, run_pipeline: Callable[[str, list[str]], int]) -> list[str]:
    from recall_api.infra.container import Container

    c = Container(settings)
    with c.engine.connect() as conn:
        ids = [r[0] for r in conn.execute(text("SELECT id FROM scans WHERE status = 'processed' ORDER BY created_at"))]
    lines = []
    for scan_id in ids:
        scan = c.scans.get(scan_id)
        name = scan.folder.removeprefix("scans/")
        episode = settings.data_dir / "blobs" / scan.folder / "episode"
        if not episode.exists():
            continue
        folder = settings.data_dir / "regression" / name
        folder.mkdir(parents=True, exist_ok=True)
        previous = sorted(folder.glob("*.json"))
        out = folder / f"{datetime.now(UTC):%Y-%m-%dT%H%M%SZ}.json"
        code = run_pipeline(name, [str(episode), "--scan-id", scan_id, "--no-post", "--out", str(out)])
        if code != 0 or not out.exists():
            lines.append(f"- {name}: pipeline failed (exit {code})")
            continue
        if previous:
            diff = compare(json.loads(previous[-1].read_text()), json.loads(out.read_text()))
            lines.append(
                f"- {name}: {diff['same']} same, {len(diff['shifted'])} shifted {diff['shifted']}, "
                f"{len(diff['missing'])} missing {diff['missing']}, {diff['new']} new"
            )
        else:
            lines.append(f"- {name}: first run, baseline saved")
    report = settings.data_dir / "regression" / "report.md"
    report.parent.mkdir(parents=True, exist_ok=True)
    with report.open("a") as f:
        f.write(f"\n## {datetime.now(UTC):%Y-%m-%d %H:%M}Z\n" + "\n".join(lines or ["- no processed scans"]) + "\n")
    for line in lines:
        log.info("regression %s", line)
    return lines
