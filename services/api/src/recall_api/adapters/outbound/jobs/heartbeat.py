"""The scan worker's heartbeat: a file the worker touches every few seconds, and the API reads to tell whether
anyone is processing scans. A file, because the worker and the API are separate processes sharing data/."""

from __future__ import annotations

import threading
from datetime import UTC, datetime
from pathlib import Path

from recall_api.application.ports import Clock


class FileHeartbeat:
    EVERY_S = 20  # how often the worker beats
    MAX_AGE_S = 90  # older than this: the worker isn't running

    def __init__(self, path: Path, clock: Clock) -> None:
        self.path, self.clock = path, clock

    def beat(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(self.clock.now().astimezone(UTC).isoformat())

    def alive(self) -> bool:
        try:
            last = datetime.fromisoformat(self.path.read_text().strip())
        except (OSError, ValueError):
            return False  # never started, or a damaged file
        return (self.clock.now() - last).total_seconds() < self.MAX_AGE_S

    def start_beating(self) -> threading.Thread:
        """Beats from a background thread: a scheduled task would wait behind a two-minute scan job and look dead."""
        stop = threading.Event()

        def loop() -> None:
            while not stop.is_set():
                self.beat()
                stop.wait(self.EVERY_S)

        t = threading.Thread(target=loop, name="worker-heartbeat", daemon=True)
        t.start()
        return t
