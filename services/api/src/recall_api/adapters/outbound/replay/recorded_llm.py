"""`make demo`: the Guide's model replies replayed from a real recorded run (samples/replay/), so it works with no keys.

A reply is looked up by the question and the step (how many replies the model had already given). Object ids are
created fresh when the demo memory is built, so the recording never depends on them: with find_object saying where,
the model's calls carry only names. Every answer says it is recorded (`model`).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from recall_api.application.ports import ChatReply, LlmProvider, ModelUnavailable, ToolCall


class NotRecorded(ModelUnavailable):
    """The demo has no recording for this question."""


def _key(messages: list[dict[str, Any]]) -> tuple[str, int]:
    question = next(m["content"] for m in messages if m["role"] == "user")
    step = sum(1 for m in messages if m["role"] == "assistant")
    return question.strip(), step


class RecordedLlm:
    def __init__(self, path: Path, model: str = "replay:muse-spark-open (recorded)") -> None:
        self.model = model
        self.replies: dict[tuple[str, int], ChatReply] = {}
        for line in path.read_text().splitlines():
            r = json.loads(line)
            calls = [ToolCall(c["id"], c["name"], c["arguments"]) for c in r["reply"]["tool_calls"]]
            self.replies[(r["question"], r["step"])] = ChatReply(r["reply"]["text"], calls, self.model)
        self.questions = sorted({q for q, _ in self.replies})

    def chat(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]]) -> ChatReply:
        reply = self.replies.get(_key(messages))
        if reply is None:
            raise NotRecorded("This question isn't in the recorded demo. Try: " + "; ".join(self.questions))
        return reply


class RecordingLlm:
    """`make record`: passes every call to the real model and keeps the replies for RecordedLlm."""

    def __init__(self, inner: LlmProvider) -> None:
        self.inner, self.model, self.lines = inner, inner.model, []

    def chat(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]]) -> ChatReply:
        reply = self.inner.chat(messages, tools)
        question, step = _key(messages)
        calls = [{"id": c.id, "name": c.name, "arguments": c.arguments} for c in reply.tool_calls]
        self.lines.append({"question": question, "step": step, "reply": {"text": reply.text, "tool_calls": calls}})
        return reply
