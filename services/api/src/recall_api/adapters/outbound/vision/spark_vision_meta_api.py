"""VisionProvider on Muse Spark 1.1 (Meta Model API, image input as a data URL): the Verifier's tie-break only.
Request shape as verified by `make probes` (docs/verification.md, item 4)."""

from __future__ import annotations

import base64

import httpx

BASE = "https://api.meta.ai/v1"


class SparkVisionMetaApi:
    def __init__(self, api_key: str, model: str = "muse-spark-1.1", timeout: float = 30) -> None:
        self.model = model
        self.client = httpx.Client(headers={"Authorization": f"Bearer {api_key}"}, timeout=timeout)

    def is_visible(self, label: str, jpeg: bytes) -> str:
        """'yes', 'no' or 'unsure' (anything unclear counts as unsure, which never downgrades)."""
        image = "data:image/jpeg;base64," + base64.b64encode(jpeg).decode()
        body = {"model": self.model, "max_tokens": 400, "messages": [{"role": "user", "content": [
            {"type": "text", "text": f"Is a {label} visible in this photo? Answer yes, no or unsure."},
            {"type": "image_url", "image_url": {"url": image}}]}]}  # fmt: skip
        try:
            r = self.client.post(f"{BASE}/chat/completions", json=body)
            r.raise_for_status()
            text = (r.json()["choices"][0]["message"].get("content") or "").strip().lower()
        except httpx.HTTPError:
            return "unsure"
        for word in ("yes", "no", "unsure"):
            if text.startswith(word):
                return word
        return "unsure"
