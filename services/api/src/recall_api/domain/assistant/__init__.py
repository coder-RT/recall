"""Grounding: a spoken answer may only state places, distances and times that a tool returned."""

from .grounding import GroundingReport, check_grounding
from .when import is_plural, spoken_when

__all__ = ["GroundingReport", "check_grounding", "is_plural", "spoken_when"]
