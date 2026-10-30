"""Spatial relations from geometry (never from a language model). Thresholds come from config/spatial.yaml."""

from .relations import HeightBand, Relation, SpatialConfig, height_band, relate, shelf_level

__all__ = ["HeightBand", "Relation", "SpatialConfig", "height_band", "relate", "shelf_level"]
