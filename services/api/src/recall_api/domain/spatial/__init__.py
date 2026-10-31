"""Spatial relations from geometry (never from a language model). Thresholds come from config/spatial.yaml."""

from .lift import CameraView, clock_and_distance, lift_box
from .relations import HeightBand, Relation, SpatialConfig, height_band, relate, shelf_level

__all__ = [
    "CameraView",
    "HeightBand",
    "Relation",
    "SpatialConfig",
    "clock_and_distance",
    "height_band",
    "lift_box",
    "relate",
    "shelf_level",
]
