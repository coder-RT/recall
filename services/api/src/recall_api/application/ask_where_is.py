"""The Guide agent: a Meta model calls tools; every place, distance and time it says must come from a tool."""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from typing import Any

from recall_api.application.ports import AnswerRecord, Clock, LlmProvider
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
7. Values in set_by_user come from the user; say them plainly, they are the most reliable.
8. find_object already says where each match is; call describe_location only for size or the user's note.
9. Asked why, or how sure: call explain and say what it returned (sightings, scans, when, how sure)."""


@dataclass
class AnswerResult:
    text: str
    grounded: bool
    object_id: str | None
    tool_calls: int
    model: str
    latency_ms: int
    answer_id: str | None = None


def fallback_sentence(outputs: list[str]) -> str:
    """The best grounded answer without the model: built only from tool output."""
    facts: dict[str, Any] = {}
    for o in outputs:
        try:
            out = json.loads(o)
        except json.JSONDecodeError:
            continue
        if out.get("matches"):  # find_object: the newest match, which carries its place
            facts.update(out["matches"][0])
        out.pop("matches", None)
        facts.update(out)
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


class NoAnswerLog:
    def record(self, answer) -> None: ...
    def get(self, answer_id):
        return None

    def recent(self, home_id, limit=100):
        return []


class AskWhereIs:
    def __init__(
        self, llm: LlmProvider, tools: Tools, tool_schemas: list[dict], homes: HomeRepository, answers=None,
        clock: Clock | None = None, new_id=None, provider: str = "",
    ) -> None:  # fmt: skip
        self.llm, self.tools, self.schemas, self.homes = llm, tools, tool_schemas, homes
        self.answers, self.clock, self.new_id, self.provider = answers or NoAnswerLog(), clock, new_id, provider

    def __call__(
        self, home_id: str, question: str, session_id: str | None = None, about: str | None = None
    ) -> AnswerResult:
        t0 = time.perf_counter()
        ctx = ToolContext(home_id=home_id, session_id=session_id)
        home = self.homes.get(home_id)
        places = {lm.label for lm in home.landmarks} | {lm.room for lm in home.landmarks if lm.room} if home else set()
        user = question if not session_id else f"{question}\n(guidance session_id: {session_id})"
        if about:
            user += f"\n(the thing the last answer was about: object_id {about})"
        messages: list[dict[str, Any]] = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": user}]
        steps: list[dict[str, Any]] = []
        tokens = {"prompt_tokens": 0, "completion_tokens": 0}
        result = self._loop(messages, ctx, places, steps, tokens)
        # an answer that names a thing's place must rest on at least one sighting; otherwise it isn't said
        if result.object_id and not ctx.observation_ids:
            result = AnswerResult(fallback_sentence([]), False, None, result.tool_calls, result.model, 0)
        result.latency_ms = self._ms(t0)
        if self.new_id and self.clock:
            result.answer_id = self.new_id("ans")
            self.answers.record(AnswerRecord(
                result.answer_id, home_id, self.clock.now(), question, result.text, result.grounded, result.object_id,
                steps, list(dict.fromkeys(ctx.observation_ids)), self.provider, self.llm.model,
                tokens["prompt_tokens"] or None, tokens["completion_tokens"] or None, result.latency_ms,
            ))  # fmt: skip
        return result

    def _loop(self, messages, ctx: ToolContext, places: set[str], steps: list, tokens: dict) -> AnswerResult:
        t0 = time.perf_counter()
        calls = 0
        corrected = False
        for _ in range(MAX_STEPS):
            ts = time.perf_counter()
            reply = self.llm.chat(messages, self.schemas)
            steps.append({"kind": "model", "ms": self._ms(ts), "tool": None, "arguments": None, "output": None})
            for k in tokens:
                tokens[k] += (reply.usage or {}).get(k, 0)
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
                    ts = time.perf_counter()
                    out = self.tools.run(ctx, c.name, c.arguments)
                    steps.append({"kind": "tool", "ms": self._ms(ts), "tool": c.name, "arguments": c.arguments,
                                  "output": json.loads(out)})  # fmt: skip
                    messages.append({"role": "tool", "tool_call_id": c.id, "content": out})
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
