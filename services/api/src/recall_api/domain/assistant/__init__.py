"""Grounding: a spoken answer may only state places, distances and times that a tool returned."""

from .grounding import GroundingReport, check_grounding

__all__ = ["GroundingReport", "check_grounding"]
