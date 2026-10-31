"""make robot-export HOME=<id> [ROOM=<room>]: writes one room's robot export to exports/robot/<home>/ (gitignored).

Runs on the Mac against the local memory; no network, no keys. The same content GET /homes/{id}/robot-export serves.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from recall_api.adapters.outbound.export.robot_files import write
from recall_api.application.export_for_robot import RobotExportError
from recall_api.config.settings import REPO_ROOT, Settings
from recall_api.infra.container import Container


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="robot-export")
    p.add_argument("--home", default="flat")
    p.add_argument("--room", default=None)
    p.add_argument("--out", default=None, help="folder (default: exports/robot/<home>/)")
    a = p.parse_args(argv)
    c = Container(Settings.load())
    try:
        e = c.export_for_robot(a.home, a.room)
    except RobotExportError as err:
        print(err, file=sys.stderr)
        return 2
    folder = Path(a.out) if a.out else REPO_ROOT / "exports" / "robot" / a.home
    for path in write(e, folder):
        print(path.relative_to(REPO_ROOT) if path.is_relative_to(REPO_ROOT) else path)
    w, h = e.map.size
    print(
        f"{e.room}: map {w} x {h} cells at {e.map.resolution} m, {len(e.objects)} things, "
        f"{len(e.landmarks)} landmarks, {len(e.cloud)} points"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
