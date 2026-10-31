"""The Guide's tools, executed against memory. Names and parameters must match resources/tools.json (contract test)."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any
from zoneinfo import ZoneInfo

from recall_api.application.ports import Clock
from recall_api.domain.assistant import spoken_when
from recall_api.domain.memory import Home
from recall_api.domain.ports import HomeRepository, TrackedObjectRepository
from recall_api.domain.spatial import relate, shelf_level

TOOL_NAMES = ("find_object", "describe_location", "localize", "plan_route")


@dataclass
class ToolContext:
    home_id: str
    session_id: str | None = None
    outputs: list[str] = field(default_factory=list)  # every tool result, for the grounding check
    found_object: str | None = None


class Tools:
    def __init__(
        self,
        homes: HomeRepository,
        objects: TrackedObjectRepository,
        clock: Clock,
        guidance=None,
        tz: ZoneInfo | None = None,
    ) -> None:
        self.homes, self.objects, self.clock, self.guidance = homes, objects, clock, guidance
        self.tz = tz or ZoneInfo("Europe/Warsaw")

    def run(self, ctx: ToolContext, name: str, args: dict[str, Any]) -> str:
        fn = {
            "find_object": self.find_object,
            "describe_location": self.describe_location,
            "localize": self.localize,
            "plan_route": self.plan_route,
        }.get(name)
        out = fn(ctx, **args) if fn else {"error": f"unknown tool {name}"}
        text = json.dumps(out)
        ctx.outputs.append(text)
        return text

    def _when(self, t) -> str:
        return spoken_when(t, self.clock.now(), self.tz)

    def _minutes(self, t) -> int:
        return max(0, int((self.clock.now() - t).total_seconds() // 60))

    def find_object(self, ctx: ToolContext, name: str) -> dict:
        matches = []
        home = self.homes.get(ctx.home_id)
        found = []
        for o in self.objects.list_for_home(ctx.home_id):
            last = o.where()
            if last is not None and o.matches(name):
                found.append((last.seen_at, o, last))
        if not found:
            return {"result": "not_found", "name": name}
        found.sort(key=lambda f: f[0], reverse=True)
        matches = []
        for _, o, last in found[:3]:
            # where it is comes with each match, so a plain question needs no second tool call
            matches.append(
                {
                    "object_id": o.id,
                    "label": o.label,
                    "name": o.corrections.name,
                    "color": o.display_color(),
                    **(self._place(last, home) if home else {}),
                    "minutes_since_seen": self._minutes(last.seen_at),
                    "seen_when": self._when(last.seen_at),
                    "confidence": round(last.confidence, 2),
                }
            )
        ctx.found_object = matches[0]["object_id"]
        return {"result": "found", "matches": matches}

    @staticmethod
    def _place(last, home: Home) -> dict:
        rel = relate(last.position, home.landmarks)
        shelves = [lm.bbox.top_z for lm in home.landmarks if rel.landmark is lm and lm.label in ("shelf", "cabinet")]
        return {
            "room": rel.landmark.room if rel.landmark else None,
            "landmark": rel.landmark.label if rel.landmark else None,
            "relation": rel.kind,
            "shelf_level": shelf_level(last.position.z, shelves) if shelves else None,
            "height_band": rel.band.value,
        }

    def describe_location(self, ctx: ToolContext, object_id: str) -> dict:
        obj = self.objects.get(object_id)
        home: Home | None = self.homes.get(ctx.home_id)
        if obj is None or home is None or obj.where() is None:
            return {"result": "not_found"}
        last = obj.where()
        ctx.found_object = object_id
        return {
            "label": obj.label,
            "name": obj.corrections.name,
            "color": obj.display_color(),
            "size_cm": [round(v * 100) for v in obj.size_m] if obj.size_m else None,
            "note": obj.corrections.note,
            "set_by_user": sorted(k for k, v in vars(obj.corrections).items() if v not in (None, False)),
            **self._place(last, home),
            "minutes_since_seen": self._minutes(last.seen_at),
            "seen_when": self._when(last.seen_at),
            "confidence": round(last.confidence, 2),
        }

    def localize(self, ctx: ToolContext, session_id: str) -> dict:
        if self.guidance is None:
            return {"result": "unavailable", "reason": "no guidance session"}
        return self.guidance.localize(session_id)

    def plan_route(self, ctx: ToolContext, session_id: str, object_id: str) -> dict:
        if self.guidance is None:
            return {"result": "unavailable", "reason": "no guidance session"}
        return self.guidance.plan_for_agent(session_id, object_id)
