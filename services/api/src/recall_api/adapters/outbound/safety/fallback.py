"""Screens in order of preference: the first one that can run decides (Llama Prompt Guard, then Muse Spark). If none
can run, the message is not safe (fails closed)."""

from __future__ import annotations

import logging

from recall_api.application.ports import Screening

log = logging.getLogger("recall_api.safety")


class FirstAvailable:
    def __init__(self, *screeners) -> None:
        self.screeners = screeners

    def screen(self, text: str) -> Screening:
        for s in self.screeners:
            v = s.screen(text)
            if v.reason != "unavailable":
                log.info("screened by %s: %s", getattr(s, "name", type(s).__name__), v.reason)
                return v
        return Screening(False, "unavailable")
