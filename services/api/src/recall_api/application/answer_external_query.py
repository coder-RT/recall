"""The Home Memory agent's one skill: where is a thing? Asked by another agent (a robot, glasses, an assistant).

Two checks before anything runs: the input must be one object name matching the schema (structure: free text is
refused and never reaches a model or a tool), then a Meta model (Muse Spark Open or Glimmer) checks that name; any
doubt refuses. Then the Guide's read-only tools answer: geometry decides, no model phrases it. Never the user's live
position, their own names or notes, or anything but where a thing was last seen, in the room's map frame.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

from recall_api.application.ask_where_is import fallback_sentence
from recall_api.application.audit import NoAudit
from recall_api.application.ports import PromptScreener, Screening
from recall_api.application.tools import ToolContext, Tools
from recall_api.domain.assistant import InvalidQuery, object_name
from recall_api.domain.audit import Action, Actor, Outcome
from recall_api.domain.ports import ScanRepository, TrackedObjectRepository

REFUSALS = {
    "structure": 'I only accept one object name, sent as {"object": "<name>"}: letters, digits, spaces and hyphens, '
    "up to 40 characters.",
    "injection": "That doesn't look like the name of a thing, so I won't act on it.",
}
UNAVAILABLE = "I can't check requests right now, so I'm not answering."


@dataclass
class ExternalAnswer:
    allowed: bool
    text: str
    data: dict = field(default_factory=dict)


class AnswerExternalQuery:
    def __init__(
        self, screener: PromptScreener, tools: Tools, objects: TrackedObjectRepository, scans: ScanRepository,
        audit=None,
    ) -> None:  # fmt: skip
        self.screener, self.tools, self.objects, self.scans = screener, tools, objects, scans
        self.audit = audit or NoAudit()

    def __call__(self, home_id: str, payload: object) -> ExternalAnswer:
        """`payload`: the structured input ({"object": "<name>"}), or None when the message had no data part."""
        answer, verdict, name = self._answer(home_id, payload)
        self.audit(
            Action.HOME_MEMORY_QUERY, Actor.ROBOT, Outcome.OK if answer.allowed else Outcome.REFUSED,
            target_type="object" if answer.data.get("object_id") else None, target_id=answer.data.get("object_id"),
            screen=verdict.reason, screened_by=verdict.by, found=answer.data.get("found"), asked=name,
        )  # fmt: skip
        return answer

    def _answer(self, home_id: str, payload: object) -> tuple[ExternalAnswer, Screening, str | None]:
        try:
            name = object_name(payload)
        except InvalidQuery as e:
            verdict = Screening(False, "structure", by="schema")
            return (
                ExternalAnswer(False, REFUSALS["structure"], {"refused": "structure", "why": e.reason}),
                verdict,
                None,
            )
        verdict = self.screener.screen(name)
        if not verdict.safe:
            text = REFUSALS.get(verdict.reason, UNAVAILABLE)
            return ExternalAnswer(False, text, {"refused": verdict.reason}), verdict, name
        ctx = ToolContext(home_id=home_id)
        found = self.tools.find_object(ctx, name)
        if found.get("result") != "found":
            data = {"found": False, "name": name, **self._earlier(home_id, name)}
            return ExternalAnswer(True, f"I haven't seen {name} yet.", data), verdict, name
        oid = found["matches"][0]["object_id"]
        facts = self.tools.describe_location(ctx, oid)
        ctx.outputs = [json.dumps({**facts, "name": None, "note": None})]  # the user's own words stay on the Mac
        obj = self.objects.get(oid)
        where = obj.where()
        scan = self.scans.get(where.scan_id)
        data = {
            "found": True,
            "object_id": oid,
            "label": obj.label,
            "color": obj.display_color(),
            "room": scan.room if scan else facts.get("room"),
            "landmark": facts.get("landmark"),
            "relation": facts.get("relation"),
            "height_band": facts.get("height_band"),
            "position": [round(v, 3) for v in where.position.as_tuple()],
            "frame_id": "map",
            "last_seen": where.seen_at.isoformat(),
            "seen_when": facts.get("seen_when"),
            "confidence": round(where.confidence, 3),
        }
        spoken = fallback_sentence(ctx.outputs).replace("Your ", "The ", 1)
        return ExternalAnswer(True, spoken, {**data, "spoken": spoken}), verdict, name

    def _earlier(self, home_id: str, name: str) -> dict:
        """A thing seen only unsurely (or long gone): when it was last seen, so the caller can say so."""
        for o in self.objects.list_for_home(home_id):
            last = o.last_seen(0.0)
            if last is not None and o.matches(name):
                return {"last_seen": last.seen_at.isoformat(), "confidence": round(last.confidence, 3)}
        return {}
