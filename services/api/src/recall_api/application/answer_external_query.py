"""The Home Memory agent's one skill: "where is X?" from another agent (a robot, glasses, another assistant).

Every message is screened first (Llama Prompt Guard); nothing runs unless it passes. Then the Guide's read-only tools
answer it: geometry decides, no model phrases it. Never the user's live position, their own names or notes, or
anything but where a thing was last seen, in the room's map frame.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field

from recall_api.application.ask_where_is import fallback_sentence
from recall_api.application.ports import PromptScreener
from recall_api.application.tools import ToolContext, Tools
from recall_api.domain.ports import ScanRepository, TrackedObjectRepository

FILLER = re.compile(
    r"^(please\s+)?(go\s+)?(and\s+)?(find|fetch|get|bring|locate|where\s+(is|are)|where's|look\s+for)\s+|"
    r"^(my|the|a|an|our)\s+|[?.!]+$",
    re.IGNORECASE,
)


@dataclass
class ExternalAnswer:
    allowed: bool
    text: str
    data: dict = field(default_factory=dict)


def thing_name(text: str) -> str:
    """ "Go find my keys?" -> "keys"; a bare name stays as it is."""
    name = text.strip()
    for _ in range(4):  # filler words can stack: "please go and find my ..."
        name = FILLER.sub("", name).strip()
    return name


class AnswerExternalQuery:
    def __init__(
        self, screener: PromptScreener, tools: Tools, objects: TrackedObjectRepository, scans: ScanRepository
    ) -> None:
        self.screener, self.tools, self.objects, self.scans = screener, tools, objects, scans

    def __call__(self, home_id: str, text: str) -> ExternalAnswer:
        verdict = self.screener.screen(text)
        if not verdict.safe:
            why = (
                "That message looks like an attempt to give me instructions, so I won't act on it."
                if verdict.reason == "attack"
                else "I can't check messages right now, so I'm not answering. The owner can turn the safety check on."
            )
            return ExternalAnswer(False, why, {"refused": verdict.reason})
        name = thing_name(text)
        ctx = ToolContext(home_id=home_id)
        found = self.tools.find_object(ctx, name)
        if found.get("result") != "found":
            return ExternalAnswer(
                True, f"I haven't seen {name} yet.", {"found": False, "name": name, **self._earlier(home_id, name)}
            )
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
        return ExternalAnswer(True, spoken, {**data, "spoken": spoken})

    def _earlier(self, home_id: str, name: str) -> dict:
        """A thing seen only unsurely (or long gone): when it was last seen, so the caller can say so."""
        for o in self.objects.list_for_home(home_id):
            last = o.last_seen(0.0)
            if last is not None and o.matches(name):
                return {"last_seen": last.seen_at.isoformat(), "confidence": round(last.confidence, 3)}
        return {}
