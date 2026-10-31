"""PromptScreener on Llama Prompt Guard 2, which runs in the pipeline's warm server on the Mac (it owns torch; the API
never imports it). Fails closed: if the screen can't run, the message is not safe to act on."""

from __future__ import annotations

import logging

import httpx

from recall_api.application.ports import Screening

log = logging.getLogger("recall_api.safety")


class PromptGuardViaPipeline:
    name = "prompt-guard"

    def __init__(self, url: str, device_key: str | None, timeout: float = 10) -> None:
        self.url = url.rstrip("/")
        self.headers = {"x-device-key": device_key} if device_key else {}
        self.timeout = timeout

    def screen(self, text: str) -> Screening:
        try:
            r = httpx.post(f"{self.url}/screen", json={"text": text}, headers=self.headers, timeout=self.timeout)
        except httpx.HTTPError as e:
            log.warning("prompt guard unreachable (%s): refusing", e)
            return Screening(False, "unavailable")
        if r.status_code != 200:
            log.warning("prompt guard unavailable (%s %s): refusing", r.status_code, r.text[:200])
            return Screening(False, "unavailable")
        verdict = r.json()
        return Screening(False, "attack") if verdict.get("attack") else Screening(True, "ok")
