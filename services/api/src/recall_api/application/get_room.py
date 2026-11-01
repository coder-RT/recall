"""The remembered room model of a home (floor, walls, furniture), as the last processed scan left it."""

from __future__ import annotations

from recall_api.domain.memory import RoomModel
from recall_api.domain.ports import HomeRepository


class GetRoom:
    def __init__(self, homes: HomeRepository) -> None:
        self.homes = homes

    def __call__(self, home_id: str) -> RoomModel | None:
        home = self.homes.get(home_id)
        return home.room_model if home else None
