"""One adapter for every Guide provider; all are OpenAI-compatible chat completions with tools (probed, see
docs/verification.md): Muse Spark Open on Baseten, Glimmer on Modal/Fireworks/LM Studio, hosted Muse Spark."""

from __future__ import annotations

import json
from typing import Any

import httpx

from recall_api.application.ports import ChatReply, ToolCall


class OpenAICompatibleLlm:
    # Muse Spark Open on Baseten reasons before it answers (reasoning_content): about 200 to 800 tokens before the
    # first visible word, so a tight cap returns an empty reply (finish_reason "length"). Measured 2026-10-31.
    def __init__(
        self, base_url: str, api_key: str | None, model: str, timeout: float = 60, max_tokens: int = 1500,
        reasoning_effort: str | None = None, transport=None,
    ) -> None:  # fmt: skip
        self.model, self.max_tokens, self.reasoning_effort = model, max_tokens, reasoning_effort
        headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
        self.client = httpx.Client(base_url=base_url.rstrip("/"), headers=headers, timeout=timeout, transport=transport)

    def chat(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]]) -> ChatReply:
        body = {
            "model": self.model,
            "messages": messages,
            "tools": tools,
            "tool_choice": "auto",
            "max_tokens": self.max_tokens,
        }
        if self.reasoning_effort:
            body["reasoning_effort"] = self.reasoning_effort
        for attempt in range(3):
            r = self.client.post("/chat/completions", json=body)
            retry = r.status_code in (429, 529) or r.status_code >= 500
            if not (retry and attempt < 2):
                break
        r.raise_for_status()
        msg = r.json()["choices"][0]["message"]
        calls = []
        for c in msg.get("tool_calls") or []:
            try:
                args = json.loads(c["function"].get("arguments") or "{}")
            except json.JSONDecodeError:
                args = {}
            calls.append(ToolCall(c.get("id", ""), c["function"]["name"], args))
        return ChatReply(text=msg.get("content"), tool_calls=calls, model=self.model)


PROVIDERS = {
    # name: (settings attribute for base url, attribute for key, attribute for model, default base)
    "baseten_spark_open": (
        "baseten_base_url",
        "baseten_api_key",
        "baseten_model",
        "https://inference.baseten.co/v1",
    ),
    "glimmer_hosted": ("glimmer_base_url", "glimmer_api_key", "glimmer_model", None),
    "lmstudio": ("lmstudio_base_url", None, "lmstudio_model", "http://localhost:1234/v1"),
    "meta": (None, "meta_muse_api_key", None, "https://api.meta.ai/v1"),
}


def from_settings(s) -> OpenAICompatibleLlm:
    base_attr, key_attr, model_attr, default = PROVIDERS[s.llm_provider]
    base = (getattr(s, base_attr) if base_attr else None) or default
    key = getattr(s, key_attr) if key_attr else None
    model = (getattr(s, model_attr) if model_attr else None) or "muse-spark-1.3"
    if not base:
        raise RuntimeError(f"{s.llm_provider} needs its base URL in .env")
    effort = s.reasoning_effort if s.llm_provider == "baseten_spark_open" else None  # only Baseten documents it
    return OpenAICompatibleLlm(base, key.get_secret_value() if key else None, model, reasoning_effort=effort)
