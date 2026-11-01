"""A robot (or the owner) asks for a room's export: refused while robot access is off unless it is the owner, and
every outcome is audited. The export itself is built by export_for_robot.py, the files by the RobotFormat port."""

from __future__ import annotations

from recall_api.application.audit import NoAudit
from recall_api.application.export_for_robot import ExportForRobot, RobotExport, RobotExportError
from recall_api.application.ports import RobotFormat
from recall_api.application.robot_access import RobotAccess
from recall_api.domain.audit import Action, Actor, Outcome


class ShareRobotExport:
    def __init__(self, export: ExportForRobot, access: RobotAccess, fmt: RobotFormat, audit=None) -> None:
        self.export, self.access, self.fmt = export, access, fmt
        self.audit = audit or NoAudit()

    def __call__(self, home_id: str, room: str | None, who: Actor, form: str) -> RobotExport:
        # the switch is about robots: the owner can always export their own map to share it
        if not (who == Actor.OWNER or self.access.export_open):
            self.audit(Action.ROBOT_EXPORT_READ, who, Outcome.REFUSED, target_type="home", target_id=home_id,
                       why="access off", form=form)  # fmt: skip
            raise RobotExportError("robot_access_off", "Robot access is off. Turn it on in the app.", 403)
        try:
            e = self.export(home_id, room)
        except RobotExportError as err:
            self.audit(Action.ROBOT_EXPORT_READ, who, Outcome.FAILED, target_type="home", target_id=home_id,
                       why=err.code, form=form)  # fmt: skip
            raise
        self.audit(Action.ROBOT_EXPORT_READ, who, target_type="home", target_id=home_id, room=e.room,
                   things=len(e.objects), scan_id=e.scan_id, form=form)  # fmt: skip
        return e

    def document(self, e: RobotExport) -> dict:
        """objects.json plus the map inline (PGM as base64) and the room outline: the JSON form of the export."""
        import base64

        w, h = e.map.size
        m = {**e.map.yaml_fields("map.pgm"), "width": w, "height": h,
             "pgm_base64": base64.b64encode(e.map.pgm()).decode()}  # fmt: skip
        return {**self.fmt.document(e), "map": m, "room_model": e.room_model}

    def package(self, e: RobotExport) -> tuple[str, bytes]:
        """The zip a robot loads, and its file name."""
        name = "recall-" + "".join(ch if ch.isalnum() else "-" for ch in e.room.lower()).strip("-") + ".zip"
        return name, self.fmt.package(e)
