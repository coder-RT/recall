"""The Guide agent: a Meta model calls tools; every place, distance and time it says must come from a tool."""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from typing import Any

from recall_api.application.ports import LlmProvider
from recall_api.application.tools import ToolContext, Tools
from recall_api.domain.assistant import check_grounding, is_plural
from recall_api.domain.ports import HomeRepository

MAX_STEPS = 6

SYSTEM = """You are Recall, a home memory for a blind or low-vision person. Answer "where is it" questions.
Rules:
1. Use the tools. Never state a place, distance or time that a tool did not return.
2. If find_object says not_found, or confidence is below 0.5, say you haven't seen it and suggest scanning the room.
3. Always say when it was seen, using seen_when exactly as given (e.g. "seen yesterday at 04:21"); never a bare time.
4. Speak one or two short sentences: the landmark first, then the shelf and height, then when it was seen.
5. Say heights as words (floor, knee, waist, chest, head height). No lists, no markdown.
6. If several things match, tell them apart by the user's name for them or their colour, and ask which one if unsure.
7. Values in set_by_user come from the user; say them plainly, they are the most reliable."""


@dataclass
class AnswerResult:
    text: str
    grounded: bool
    object_id: str | None
    tool_calls: int
    model: str
    latency_ms: int


def fallback_sentence(outputs: list[str]) -> str:
    """The best grounded answer without the model: built only from tool output."""
    facts: dict[str, Any] = {}
    for o in outputs:
        try:
            facts.update(json.loads(o))
        except json.JSONDecodeError:
            continue
    if facts.get("result") == "not_found" or "label" not in facts:
        return "I haven't seen that yet. Scan the room it might be in, and I'll remember it."
    where = f"{facts['relation'].replace('_', ' ')} the {facts['landmark']}" if facts.get("landmark") else "in the room"
    if facts.get("relation") == "near":
        where = f"near the {facts['landmark']}"
    shelf = f", shelf {facts['shelf_level']}" if facts.get("shelf_level") else ""
    thing = facts.get("name") or " ".join(x for x in (facts.get("color"), facts["label"]) if x)
    when = f"seen {facts['seen_when']}" if facts.get("seen_when") else ""
    verb = "are" if is_plural(facts.get("name") or facts["label"]) else "is"
    return f"Your {thing} {verb} {where}{shelf}, at {facts['height_band']} height" + (f", {when}." if when else ".")


class AskWhereIs:
    def __init__(self, llm: LlmProvider, tools: Tools, tool_schemas: list[dict], homes: HomeRepository) -> None:
        self.llm, self.tools, self.schemas, self.homes = llm, tools, tool_schemas, homes

    def __call__(self, home_id: str, question: str, session_id: str | None = None) -> AnswerResult:
        t0 = time.perf_counter()
        ctx = ToolContext(home_id=home_id, session_id=session_id)
        home = self.homes.get(home_id)
        places = {lm.label for lm in home.landmarks} | {lm.room for lm in home.landmarks if lm.room} if home else set()
        user = question if not session_id else f"{question}\n(guidance session_id: {session_id})"
        messages: list[dict[str, Any]] = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": user}]
        calls = 0
        corrected = False
        for _ in range(MAX_STEPS):
            reply = self.llm.chat(messages, self.schemas)
            if reply.tool_calls:
                messages.append(
                    {
                        "role": "assistant",
                        "content": reply.text or "",
                        "tool_calls": [
                            {
                                "id": c.id,
                                "type": "function",
                                "function": {"name": c.name, "arguments": json.dumps(c.arguments)},
                            }
                            for c in reply.tool_calls
                        ],
                    }
                )
                for c in reply.tool_calls:
                    calls += 1
                    messages.append(
                        {"role": "tool", "tool_call_id": c.id, "content": self.tools.run(ctx, c.name, c.arguments)}
                    )
                continue
            text = (reply.text or "").strip()
            report = check_grounding(text, ctx.outputs, places)
            if calls and ctx.found_object is None:
                # rule 2 in code: nothing was found, so the fixed "not seen" sentence answers, not the model
                break
            if text and calls and report.ok:
                return AnswerResult(text, True, ctx.found_object, calls, self.llm.model, self._ms(t0))
            if not corrected:  # one correction, then the code answers
                corrected = True
                messages.append({"role": "assistant", "content": text})
                missing = ", ".join(report.unsupported_places + report.unsupported_numbers)
                problem = "you did not use the tools" if not calls else f"these are not in the tool results: {missing}"
                messages.append(
                    {"role": "user", "content": f"That breaks rule 1 ({problem}). Use the tools, then answer."}
                )
                continue
            break
        return AnswerResult(fallback_sentence(ctx.outputs), True, ctx.found_object, calls, self.llm.model, self._ms(t0))

    @staticmethod
    def _ms(t0: float) -> int:
        return int((time.perf_counter() - t0) * 1000)
