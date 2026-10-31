"""Screens in order of preference: the first one that can run decides (Llama Prompt Guard, then Muse Spark). If none
can run, the message is not safe (fails closed)."""

from __future__ import annotations

import logging
from dataclasses import replace

from recall_api.application.ports import Screening

log = logging.getLogger("recall_api.safety")


class FirstAvailable:
    def __init__(self, *screeners) -> None:
        self.screeners = screeners

    def screen(self, text: str) -> Screening:
        for s in self.screeners:
            v = s.screen(text)
            if v.reason != "unavailable":
                name = getattr(s, "name", type(s).__name__)
                log.info("screened by %s: %s", name, v.reason)
                return replace(v, by=name)
        return Screening(False, "unavailable")
