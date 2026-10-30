"""After a scan the user can fix what the models were unsure about: name, colour, height, a note, confirm or remove.
Their values win over measurements and later scans never overwrite them."""

from __future__ import annotations

from dataclasses import dataclass

from recall_api.domain.memory import COLOR_NAMES, TrackedObject
from recall_api.domain.ports import TrackedObjectRepository

_UNSET = object()


class CorrectionError(Exception):
    def __init__(self, code: str, message: str, status: int = 422) -> None:
        super().__init__(message)
        self.code, self.message, self.status = code, message, status


@dataclass
class CorrectionInput:
    """Only the fields the user sent; None clears a field back to the measured value."""

    name: object = _UNSET
    color: object = _UNSET
    height_m: object = _UNSET
    note: object = _UNSET
    confirmed: object = _UNSET


class CorrectObject:
    def __init__(self, objects: TrackedObjectRepository) -> None:
        self.objects = objects

    def _get(self, home_id: str, object_id: str) -> TrackedObject:
        obj = self.objects.get(object_id)
        if obj is None or obj.home_id != home_id:
            raise CorrectionError("not_found", "No such object in this home.", 404)
        return obj

    def update(self, home_id: str, object_id: str, change: CorrectionInput) -> TrackedObject:
        obj = self._get(home_id, object_id)
        c = obj.corrections
        if change.name is not _UNSET:
            c.name = _text(change.name, 40, "name")
        if change.color is not _UNSET:
            color = _text(change.color, 20, "color")
            if color is not None and color.lower() not in COLOR_NAMES:
                raise CorrectionError("bad_color", f"Colour must be one of: {', '.join(COLOR_NAMES)}.")
            c.color = color.lower() if color else None
        if change.height_m is not _UNSET:
            h = change.height_m
            if h is not None and not (isinstance(h, int | float) and 0 <= h <= 3):
                raise CorrectionError("bad_height", "Height is in metres above the floor, between 0 and 3.")
            c.height_m = float(h) if h is not None else None
        if change.note is not _UNSET:
            c.note = _text(change.note, 200, "note")
        if change.confirmed is not _UNSET:
            c.confirmed = bool(change.confirmed)
        self.objects.save(obj)
        return obj

    def remove(self, home_id: str, object_id: str) -> None:
        self._get(home_id, object_id)
        self.objects.delete(object_id)


def _text(value: object, limit: int, field: str) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if len(text) > limit:
        raise CorrectionError("too_long", f"The {field} can be at most {limit} characters.")
    return text or None
