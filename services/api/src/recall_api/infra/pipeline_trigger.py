"""Starts the pipeline as a separate process on the Mac (it owns torch; the API never imports it)."""

from __future__ import annotations

import shlex
import subprocess
from pathlib import Path


class SubprocessPipelineTrigger:
    def __init__(self, command: str, cwd: Path, log_dir: Path) -> None:
        self.command, self.cwd, self.log_dir = command, cwd, log_dir

    def start(self, scan_id: str, episode_dir: str) -> None:
        self.log_dir.mkdir(parents=True, exist_ok=True)
        log = (self.log_dir / f"{scan_id}.log").open("ab")
        subprocess.Popen(
            [*shlex.split(self.command), episode_dir, "--scan-id", scan_id],
            cwd=self.cwd,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
