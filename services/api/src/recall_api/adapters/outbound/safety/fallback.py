"""Screens in layers: each screen that can run must pass. Llama Prompt Guard first (classic injections and
jailbreaks, in milliseconds); then Muse Spark (is this only a request for an object?), which Prompt Guard isn't built
to judge: measured on 2026-10-31, Prompt Guard alone let 20 of 24 off-scope attacks through (docs/verification.md).
A screen that can't run is skipped; if none can run, the message is not safe (fails closed)."""

from __future__ import annotations

import logging
from dataclasses import replace

from recall_api.application.ports import Screening

log = logging.getLogger("recall_api.safety")


class Layered:
    def __init__(self, *screeners) -> None:
        self.screeners = screeners

    def screen(self, text: str) -> Screening:
        ran: list[str] = []
        for s in self.screeners:
            v = s.screen(text)
            name = getattr(s, "name", type(s).__name__)
            if v.reason == "unavailable":
                continue
            ran.append(name)
            if not v.safe:
                log.info("refused by %s: %s", name, v.reason)
                return replace(v, by=name)  # the first layer that refuses decides; later ones aren't asked
        if not ran:
            return Screening(False, "unavailable")
        return Screening(True, "ok", by="+".join(ran))
