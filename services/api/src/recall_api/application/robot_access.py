"""Robot access: whether robots (and other agents) may read this home's memory, the robot export and the Home Memory
agent. Off by default; the owner turns it on from the phone. The Mac's env flags (ROBOT_EXPORT_ENABLED,
HOME_MEMORY_A2A_ENABLED) still turn each part on for a Mac-only setup."""

from __future__ import annotations

from recall_api.application.ports import OwnerSettings

KEY = "robot_access"


class RobotAccess:
    def __init__(self, store: OwnerSettings, export_flag: bool = False, a2a_flag: bool = False) -> None:
        self.store, self.export_flag, self.a2a_flag = store, export_flag, a2a_flag

    @property
    def on(self) -> bool:
        return self.store.get(KEY) == "on"

    def turn(self, on: bool) -> bool:
        self.store.put(KEY, "on" if on else "off")
        return self.on

    @property
    def export_open(self) -> bool:
        return self.on or self.export_flag

    @property
    def a2a_open(self) -> bool:
        return self.on or self.a2a_flag
