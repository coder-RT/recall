"""The warm pipeline (`recall-pipeline serve`, MapAnything already loaded), reached over 127.0.0.1. Every call is best
effort: when the server isn't running, the caller starts the pipeline as a fresh process instead."""

from __future__ import annotations

import logging
import threading

import httpx

log = logging.getLogger("recall_api.pipeline")


class PipelineServer:
    def __init__(self, url: str, device_key: str | None) -> None:
        self.url = url.rstrip("/")
        self.headers = {"x-device-key": device_key} if device_key else {}

    def up(self) -> bool:
        try:
            return httpx.get(f"{self.url}/health", headers=self.headers, timeout=1).status_code == 200
        except httpx.HTTPError:
            return False

    def warm(self) -> None:
        """Asks it to load the model, without waiting (a scan has started uploading)."""

        def ask() -> None:
            try:
                httpx.post(f"{self.url}/warm", headers=self.headers, timeout=2)
            except httpx.HTTPError:
                log.info("pipeline server not running; the scan will start a fresh pipeline process")

        threading.Thread(target=ask, daemon=True).start()

    def run(self, args: list[str], log_file: str) -> int | None:
        """Runs one job and waits for it; None when the server can't be reached (then run it as a process)."""
        if not self.up():
            return None
        try:
            r = httpx.post(f"{self.url}/jobs", json={"args": args, "log": log_file}, headers=self.headers, timeout=None)
            r.raise_for_status()
            return int(r.json()["code"])
        except httpx.HTTPError as e:
            log.warning("pipeline server failed (%s); running the pipeline as a process", e)
            return None
