"""The scan job queue and its scheduler (Huey on SQLite: no extra server). One worker runs one job at a time,
because MapAnything needs most of the Mac's GPU memory.

    worker:  uv run huey_consumer recall_api.infra.jobs.huey -w 1      (make worker)

- process_scan: runs the pipeline for an uploaded scan; retried twice, then the scan is marked failed.
- nightly_regression (03:17 every night): re-runs every processed scan without posting and compares the objects
  with the previous run (data/regression/). SAM answers are cached per scan, so a re-run makes no model calls."""

from __future__ import annotations

import logging
import shlex
import subprocess
from datetime import UTC, datetime
from pathlib import Path

from huey import SqliteHuey, crontab

from recall_api.config.settings import REPO_ROOT, Settings
from recall_api.infra.pipeline_server import PipelineServer

log = logging.getLogger("recall_api.jobs")
settings = Settings.load()
settings.data_dir.mkdir(parents=True, exist_ok=True)
huey = SqliteHuey("recall", filename=str(settings.data_dir / "jobs.db"))
key = settings.device_key.get_secret_value() if settings.device_key else None
server = PipelineServer(settings.pipeline_server, key)


def run_pipeline(name: str, args: list[str], warm: PipelineServer | None = None) -> int:
    """The pipeline in its own environment (it owns torch); output goes to data/logs/<name>.log. On the warm server
    when it runs (no model load), else as a fresh process."""
    settings.log_dir.mkdir(parents=True, exist_ok=True)
    log_file = settings.log_dir / f"{name}.log"
    code = (warm or server).run(args, str(log_file))
    if code is not None:
        return code
    with log_file.open("ab") as out:
        out.write(f"\n=== {datetime.now(UTC):%Y-%m-%d %H:%M:%S}Z {' '.join(args[:1])} ===\n".encode())
        out.flush()
        return subprocess.run(
            [*shlex.split(settings.pipeline_command), *args], cwd=REPO_ROOT, stdout=out, stderr=subprocess.STDOUT
        ).returncode


@huey.task(retries=2, retry_delay=60, context=True)
def process_scan(name: str, scan_id: str, episode_dir: str, task=None) -> None:
    log.info("job: process %s", name)
    code = run_pipeline(name, [episode_dir, "--scan-id", scan_id])
    if code == 0:
        return
    if task is None or task.retries == 0:  # last attempt: tell the phone
        from recall_api.domain.audit import Action, Actor, Outcome
        from recall_api.domain.memory import ScanStatus
        from recall_api.infra.container import Container

        c = Container(settings)
        scan = c.scans.get(scan_id)
        if scan is not None:
            scan.status = ScanStatus.FAILED
            scan.detail = f"Processing failed (exit {code}). The Mac's log is data/logs/{name}.log."
            c.scans.save(scan)
            c.auditor(Action.SCAN_FAILED, Actor.PIPELINE, Outcome.FAILED, target_type="scan", target_id=scan_id,
                      room=scan.room, exit=code)  # fmt: skip
    raise RuntimeError(f"pipeline exited {code} for {name}")


@huey.periodic_task(crontab(hour="3", minute="17"))
def nightly_regression() -> None:
    from recall_api.infra.regression import run

    run(settings, run_pipeline)


class QueuedPipelineTrigger:
    """PipelineTrigger: puts the scan on the queue; the worker picks it up."""

    def start(self, name: str, scan_id: str, episode_dir: str) -> None:
        process_scan(name, scan_id, episode_dir)

    def warm(self) -> None:
        server.warm()


def episode_dirs(data_dir: Path) -> list[Path]:
    return sorted(p for p in (data_dir / "blobs" / "scans").glob("*/episode") if (p / "manifest.json").exists())
