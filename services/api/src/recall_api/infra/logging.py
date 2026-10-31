"""Logging setup: readable lines on the console, JSON lines in data/logs/api.jsonl (rotated), each with the trace id.
Never log keys, request bodies, audio, images or the user's position."""

from __future__ import annotations

import json
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path

from opentelemetry import trace


class JsonLines(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        ctx = trace.get_current_span().get_span_context()
        line = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S") + f".{int(record.msecs):03d}",
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        if ctx.is_valid:
            line["trace_id"] = f"{ctx.trace_id:032x}"
            line["span_id"] = f"{ctx.span_id:016x}"
        line.update(getattr(record, "fields", {}))
        if record.exc_info:
            line["error"] = self.formatException(record.exc_info)
        return json.dumps(line, default=str)


def configure(log_dir: Path, level: str = "INFO") -> None:
    log_dir.mkdir(parents=True, exist_ok=True)
    root = logging.getLogger()
    root.setLevel(level)
    for h in list(root.handlers):
        if getattr(h, "_recall", False):
            root.removeHandler(h)
    console = logging.StreamHandler()
    console.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
    file = RotatingFileHandler(log_dir / "api.jsonl", maxBytes=5_000_000, backupCount=5, encoding="utf-8")
    file.setFormatter(JsonLines())
    for h in (console, file):
        h._recall = True  # type: ignore[attr-defined]
        root.addHandler(h)
