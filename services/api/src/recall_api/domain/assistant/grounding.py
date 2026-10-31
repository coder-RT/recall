from __future__ import annotations

import re
from dataclasses import dataclass

_NUMBER = re.compile(r"(?<![\w.])(\d+(?:[.,]\d+)?)")
_CLOCK = re.compile(r"\b(\d{1,2}):(\d{2})\b")


@dataclass(frozen=True)
class GroundingReport:
    ok: bool
    unsupported_numbers: tuple[str, ...]
    unsupported_places: tuple[str, ...]


def _numbers(text: str) -> set[float]:
    out: set[float] = set()
    for h, m in _CLOCK.findall(text):
        out.add(float(f"{int(h)}.{m}"))
    stripped = _CLOCK.sub(" ", text)
    for n in _NUMBER.findall(stripped):
        out.add(round(float(n.replace(",", ".")), 1))
    return out


def check_grounding(answer: str, tool_outputs: list[str], place_vocabulary: set[str]) -> GroundingReport:
    """Every number and every known place name in the answer must appear in some tool output.

    `place_vocabulary` is every landmark label and room name in the home, so the check catches a place the model
    knows about but no tool returned for this question. Unknown words are not places and are not checked.
    """
    evidence = " ".join(tool_outputs).lower()
    allowed = _numbers(evidence)
    numbers = [n for n in _numbers(answer) if n not in allowed]
    # spoken "one"/"two" metres are fine to skip; digits are what models use for facts
    places = sorted(p for p in place_vocabulary if p and re.search(rf"\b{re.escape(p.lower())}\b", answer.lower()))
    missing_places = tuple(p for p in places if p.lower() not in evidence)
    bad_numbers = tuple(str(n) for n in sorted(numbers))
    return GroundingReport(
        ok=not bad_numbers and not missing_places, unsupported_numbers=bad_numbers, unsupported_places=missing_places
    )
