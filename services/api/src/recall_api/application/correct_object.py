"""After a scan the user can fix what the models were unsure about: name, colour, height, a note, confirm or remove.
Their values win over measurements and later scans never overwrite them."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

from recall_api.application.audit import NoAudit
from recall_api.application.ports import Clock
from recall_api.domain.audit import Action, Actor
from recall_api.domain.memory import COLOR_NAMES, Rejection, TrackedObject
from recall_api.domain.ports import HomeRepository, TrackedObjectRepository

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
    def __init__(
        self, objects: TrackedObjectRepository, homes: HomeRepository, clock: Clock, new_id: Callable[[str], str],
        audit=None,
    ) -> None:  # fmt: skip
        self.objects, self.homes, self.clock, self.new_id = objects, homes, clock, new_id
        self.audit = audit or NoAudit()

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
        changed = sorted(
            k for k in ("name", "color", "height_m", "note", "confirmed") if getattr(change, k) is not _UNSET
        )
        self.audit(Action.OBJECT_CORRECTED, Actor.OWNER, target_type="object", target_id=obj.id, label=obj.label,
                   fields=changed, confirmed=c.confirmed)  # fmt: skip
        return obj

    def remove(self, home_id: str, object_id: str) -> None:
        """ "Not there, forget it": the thing goes, and later scans won't bring the same mistake back."""
        obj = self._get(home_id, object_id)
        where = obj.where()
        home = self.homes.get(home_id)
        if where is not None and home is not None:
            home.rejections.append(Rejection(self.new_id("rej"), obj.label, where.position, self.clock.now()))
            self.homes.save(home)
        self.objects.delete(object_id)
        self.audit(Action.OBJECT_FORGOTTEN, Actor.OWNER, target_type="object", target_id=object_id, label=obj.label)


def _text(value: object, limit: int, field: str) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if len(text) > limit:
        raise CorrectionError("too_long", f"The {field} can be at most {limit} characters.")
    return text or None
