"""Speech to text for a question: the audio goes to Muse Voice Transcribe (the only speech model), and the audit
records that it left the Mac, how much and how it went. Never the words: they are the owner's."""

from __future__ import annotations

import time
from dataclasses import dataclass

from recall_api.application.audit import NoAudit
from recall_api.application.ports import Transcriber
from recall_api.domain.audit import Action, Actor, Outcome

MODEL = "muse-voice-transcribe-1.0"


@dataclass(frozen=True)
class Transcript:
    text: str
    model: str
    latency_ms: int


class TranscribeSpeech:
    def __init__(self, transcriber: Transcriber, audit=None) -> None:
        self.transcriber = transcriber
        self.audit = audit or NoAudit()

    def __call__(self, audio: bytes, content_type: str) -> Transcript:
        t0 = time.perf_counter()
        try:
            text = self.transcriber.transcribe(audio, content_type)
        except Exception as e:
            self.audit(Action.VOICE_TRANSCRIBED, Actor.OWNER, Outcome.FAILED, model=MODEL, bytes=len(audio),
                       format=content_type, why=type(e).__name__)  # fmt: skip
            raise
        ms = int((time.perf_counter() - t0) * 1000)
        self.audit(Action.VOICE_TRANSCRIBED, Actor.OWNER, model=MODEL, bytes=len(audio), format=content_type,
                   latency_ms=ms, words=len(text.split()))  # fmt: skip
        return Transcript(text, MODEL, ms)
