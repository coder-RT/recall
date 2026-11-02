"""Everything Recall remembers in a home, for Found and Find: where each thing is in words (room, furniture, relation,
shelf, height) and whether it is trusted at the owner's level. Found shows them all and asks the owner to check the
rest; everything else (the Guide, Find, maps, robots) uses only the trusted ones."""

from __future__ import annotations

from dataclasses import dataclass

from recall_api.application.trust import TrustPolicy
from recall_api.domain.memory import Home, Observation, TrackedObject, Trust
from recall_api.domain.ports import HomeRepository, ScanRepository, TrackedObjectRepository
from recall_api.domain.spatial import Relation, relate, shelf_level


class NoSuchHome(LookupError):
    pass


@dataclass(frozen=True)
class ThingView:
    thing: TrackedObject
    where: Observation  # the newest sighting, trusted or not
    room: str | None
    relation: Relation
    shelf_level: int | None
    trusted: bool
    needs_review: bool


class ListThings:
    def __init__(
        self, homes: HomeRepository, objects: TrackedObjectRepository, scans: ScanRepository, trust: TrustPolicy
    ) -> None:
        self.homes, self.objects, self.scans, self.trust = homes, objects, scans, trust

    def all(self, home_id: str) -> list[ThingView]:
        home = self.home(home_id)
        level = self.trust.level
        return [v for obj in self.objects.list_for_home(home_id) if (v := self.view(home, obj, level))]

    def home(self, home_id: str) -> Home:
        home = self.homes.get(home_id)
        if home is None:
            raise NoSuchHome(home_id)
        return home

    def view(self, home: Home, obj: TrackedObject, level: Trust | None = None) -> ThingView | None:
        level = level or self.trust.level
        where = obj.where()
        if where is None:
            return None
        rel = relate(where.position, home.landmarks)
        room = rel.landmark.room if rel.landmark else None
        if room is None and (scan := self.scans.get(where.scan_id)) is not None:
            room = scan.room  # not near any furniture: the room it was scanned in
        shelves = [lm.bbox.top_z for lm in home.landmarks if lm.label == "shelf" and rel.landmark is lm]
        return ThingView(
            thing=obj,
            where=where,
            room=room,
            relation=rel,
            shelf_level=shelf_level(where.position.z, shelves) if shelves else None,
            trusted=obj.where(level) is not None,
            needs_review=obj.needs_review(level),
        )
