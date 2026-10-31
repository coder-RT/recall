"""Muse Voice Transcribe, the only speech model (probed: docs/verification.md). ENDPOINTING mode detects turns."""

from __future__ import annotations

import json

import httpx

ENDPOINT = "https://api.meta.ai/v1/asr/transcribe"


class MuseTranscriber:
    def __init__(self, api_key: str, timeout: float = 30) -> None:
        self.client = httpx.Client(headers={"Authorization": f"Bearer {api_key}"}, timeout=timeout)

    def transcribe(self, audio: bytes, content_type: str) -> str:
        if not content_type.startswith(("audio/wav", "audio/x-wav", "audio/wave")):
            raise ValueError("send mono 16-bit PCM WAV at 16 or 24 kHz")
        request = {"model": "muse-voice-transcribe-1.0", "audioEncoding": "WAV", "mode": "ENDPOINTING"}
        files = {"request": (None, json.dumps(request), "application/json"), "audio": ("q.wav", audio, "audio/wav")}
        r = self.client.post(ENDPOINT, files=files)
        r.raise_for_status()
        return (r.json().get("transcript") or "").strip()
