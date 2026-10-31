"""ResultSink: posts the scan result to the API, which is the only writer of memory."""

from __future__ import annotations

import httpx


class ApiResultSink:
    def __init__(self, base_url: str, device_key: str) -> None:
        self.client = httpx.Client(base_url=base_url, headers={"Authorization": f"Bearer {device_key}"}, timeout=60)

    def post(self, scan_id: str, result: dict) -> None:
        r = self.client.post(f"/scans/{scan_id}/results", json=result)
        r.raise_for_status()
