"""Segmenter on SAM 3.1 (Meta Model API): one text prompt per request; boxes parsed from the documented token format.

https://dev.meta.ai/docs/sam/reading-segmentation. Masks are not decoded (their encoding is TODO(verify)); a box plus
LiDAR depth is enough to place a thing. Same request as the pipeline's adapter (the API can't import the pipeline).
"""

from __future__ import annotations

import base64
import re
import time

import httpx

from recall_api.application.ports import Mask

ENDPOINT = "https://api.meta.ai/v1/responses"
_BOX = re.compile(r"<\|box;([^|]*)\|>")


def parse_boxes(text: str, label: str) -> list[Mask]:
    out = []
    for m in _BOX.finditer(text):
        kv = dict(part.split("=", 1) for part in m.group(1).split(";") if "=" in part)
        try:
            box = (float(kv["x1"]), float(kv["y1"]), float(kv["x2"]), float(kv["y2"]))
        except KeyError:
            continue
        out.append(Mask(label=label, score=float(kv.get("c", 1.0)), mask=None, box=box))
    return out


class Sam31MetaApi:
    def __init__(self, api_key: str, timeout: float = 30) -> None:
        self.client = httpx.Client(headers={"Authorization": f"Bearer {api_key}"}, timeout=timeout)

    def segment(self, jpeg: bytes, prompts: list[str]) -> list[Mask]:
        found: list[Mask] = []
        for concept in prompts:
            body = {
                "model": "sam-3.1",
                "metadata": {"include_confidence": "true", "mask_encoding": "one_bit"},
                "input": [{"role": "user", "content": [
                    {"type": "input_text", "text": concept},
                    {"type": "input_image", "image_url": "data:image/jpeg;base64," + base64.b64encode(jpeg).decode()},
                ]}],
            }  # fmt: skip
            for attempt in range(3):
                r = self.client.post(ENDPOINT, json=body)
                if r.status_code == 429 or r.status_code >= 500:
                    time.sleep(float(r.headers.get("retry-after", 2**attempt)))
                    continue
                r.raise_for_status()
                text = "".join(
                    c.get("text", "")
                    for o in r.json().get("output", [])
                    for c in (o.get("content") or [])
                    if c.get("type") == "output_text"
                )
                found += parse_boxes(text, concept)
                break
        return found
