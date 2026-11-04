"""What someone meant after "Do you want to go back, or are you done?". A Meta model reads it, because people say
"nah, I'm good" as often as "no thank you"; it only sorts the reply and states no fact, and the phone falls back to
plain rules on "unknown". The audit records that the words left the Mac, never the words."""

from __future__ import annotations

import time
from dataclasses import dataclass

from recall_api.application.audit import NoAudit
from recall_api.application.ports import ReplyReader
from recall_api.domain.audit import Action, Actor, Outcome


@dataclass(frozen=True)
class Reply:
    intent: str
    by: str


class ReadReply:
    def __init__(self, reader: ReplyReader, audit=None) -> None:
        self.reader = reader
        self.audit = audit or NoAudit()

    def __call__(self, said: str, thing: str = "") -> Reply:
        t0 = time.perf_counter()
        intent = self.reader.read(said, thing)
        ms = int((time.perf_counter() - t0) * 1000)
        self.audit(Action.REPLY_READ, Actor.OWNER, Outcome.FAILED if intent == "unknown" else Outcome.OK,
                   model=self.reader.name, intent=intent, latency_ms=ms)  # fmt: skip
        return Reply(intent, self.reader.name)
