"""The robot export: Nav2's map files read the way Nav2 reads them, the map frame is the home frame, and only
geometry and labels leave the Mac."""

import base64
import json
from datetime import UTC, datetime

import numpy as np
import yaml
from fastapi.testclient import TestClient

from recall_api.adapters.outbound.export.robot_files import document, ply, write
from recall_api.application.export_for_robot import ExportForRobot, voxel_downsample
from recall_api.config.settings import Settings
from recall_api.domain.memory import Corrections
from recall_api.domain.navigation.occupancy import FREE, OCCUPIED, UNKNOWN, OccupancyMap, shade_to_cell
from recall_api.infra.app import create_app
from tests.fakes import FixedClock, MemoryBlobs
from tests.unit.test_matching_and_ingest import ROOM, Repos, obj


def room_points() -> np.ndarray:
    """A 2 x 1 m floor (z = 0) and a 20 cm box at x 1.5..1.7, y 0.4..0.6 standing 0.5 m tall."""
    xs, ys = np.meshgrid(np.arange(0.0, 2.0, 0.02), np.arange(0.0, 1.0, 0.02))
    floor = np.c_[xs.ravel(), ys.ravel(), np.zeros(xs.size)]
    bx, by, bz = np.meshgrid(np.arange(1.5, 1.7, 0.02), np.arange(0.4, 0.6, 0.02), np.arange(0.1, 0.5, 0.05))
    box = np.c_[bx.ravel(), by.ravel(), bz.ravel()]
    return np.vstack(
        [floor[~((floor[:, 0] >= 1.5) & (floor[:, 0] < 1.7) & (floor[:, 1] >= 0.4) & (floor[:, 1] < 0.6))], box]
    )


def test_cells_floor_free_box_occupied_outside_unknown():
    m = OccupancyMap.from_points(room_points())
    assert m.resolution == 0.1
    assert m.cells[m.cell_at(0.5, 0.5)] == FREE
    assert m.cells[m.cell_at(1.6, 0.5)] == OCCUPIED
    assert m.cells[0, 0] == UNKNOWN  # the margin round the scan: nobody saw it
    walked = OccupancyMap.from_points(room_points()[:10], walked=np.array([[0.55, 0.55]]))
    assert walked.cells[walked.cell_at(0.55, 0.55)] == FREE  # where the person walked is free


def test_pgm_shades_read_back_as_nav2_reads_them():
    m = OccupancyMap.from_points(room_points())
    data = m.pgm()
    head, pixels = data.split(b"\n255\n", 1)
    w, h = m.size
    assert head == f"P5\n{w} {h}".encode() and len(pixels) == w * h
    img = np.frombuffer(pixels, np.uint8).reshape(h, w)
    # the image's top row is the map's highest y: flipping it back gives the cells, shade by shade
    back = np.vectorize(shade_to_cell)(np.flipud(img))
    assert (back == m.cells).all()
    assert {shade_to_cell(254), shade_to_cell(0), shade_to_cell(128)} == {FREE, OCCUPIED, UNKNOWN}


def test_map_yaml_and_frame():
    m = OccupancyMap.from_points(room_points())
    y = m.yaml_fields()
    assert y == {"image": "map.pgm", "mode": "trinary", "resolution": 0.1, "origin": [-0.1, -0.1, 0.0], "negate": 0,
                 "occupied_thresh": 0.65, "free_thresh": 0.25}  # fmt: skip
    # the origin is the lower-left corner of cell (0, 0): a world point maps to the cell holding it
    assert m.cell_at(-0.1, -0.1) == (0, 0) and m.cell_at(-0.11, 0) is None


def test_voxel_downsample_and_ply():
    pts = np.array([[0.01, 0.01, 0.0], [0.02, 0.03, 0.0], [0.5, 0.5, 0.5]])
    down = voxel_downsample(pts, 0.05)
    assert len(down) == 2 and np.allclose(sorted(down[:, 0]), [0.015, 0.5])
    data = ply(down)
    assert data.startswith(b"ply\nformat binary_little_endian 1.0\n") and b"element vertex 2\n" in data
    assert len(data.split(b"end_header\n", 1)[1]) == 2 * 3 * 4


def _exporter(tmp_path):
    r = Repos()
    r.scan("s1", 10)
    r.ingest(
        "s1", {"room": ROOM, "landmarks": [obj("desk", [1.0, 0.5, 0.38])], "objects": [obj("keys", [1.0, 0.5, 0.8])]}
    )
    keys = next(o for o in r.objects.items.values() if o.label == "keys")
    keys.corrections = Corrections(name="Dad's car keys", note="spare set, blue tag")
    r.objects.save(keys)
    blobs = MemoryBlobs()
    import io

    buf = io.BytesIO()
    np.save(buf, room_points())
    blobs.put(f"{r.scans.get('s1').folder}/episode/home_cloud.npy", buf.getvalue())
    return ExportForRobot(r.homes, r.scans, r.objects, blobs, FixedClock()), r


def test_export_has_geometry_and_labels_only(tmp_path):
    export, _ = _exporter(tmp_path)
    e = export("flat")
    assert (e.room, e.scan_id) == ("Office", "s1")
    (keys,) = e.objects
    assert keys["label"] == "keys" and keys["frame_id"] == "map" and keys["orientation"] == [0.0, 0.0, 0.0, 1.0]
    assert keys["position"] == [1.0, 0.5, 0.8]
    text = json.dumps(document(e))
    assert "Dad" not in text and "blue tag" not in text  # the user's own names and notes stay on the Mac
    assert set(keys) == {"id", "label", "aliases", "color", "position", "orientation", "frame_id", "size_m",
                         "last_seen", "confidence"}  # fmt: skip
    files = {p.name for p in write(e, tmp_path / "out")}
    assert files == {"map.pgm", "map.yaml", "objects.json", "room.json", "cloud.ply"}
    assert yaml.safe_load((tmp_path / "out" / "map.yaml").read_text())["image"] == "map.pgm"


def test_endpoint_is_off_by_default_and_needs_a_key(tmp_path):
    def client(enabled: bool):
        s = Settings(RECALL_DATA_DIR=tmp_path, RECALL_DEVICE_KEY="owner", RECALL_ROBOT_KEY="robot",
                     ROBOT_EXPORT_ENABLED=enabled, RECALL_TRACES="off")  # fmt: skip
        app = create_app(s)
        export, _ = _exporter(tmp_path)
        app.state.container.__dict__["export_for_robot"] = export
        return TestClient(app)

    off = client(False)
    assert off.get("/homes/flat/robot-export", headers={"Authorization": "Bearer robot"}).status_code == 403
    assert off.get("/homes/flat/robot-export", headers={"Authorization": "Bearer owner"}).status_code == 200
    on = client(True)
    assert on.get("/homes/flat/robot-export").status_code == 401
    assert on.get("/homes/flat/robot-export", headers={"Authorization": "Bearer wrong"}).status_code == 401
    r = on.get("/homes/flat/robot-export", headers={"Authorization": "Bearer robot"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["format"] == "recall-robot-export/1" and body["frame_id"] == "map"
    assert base64.b64decode(body["map"]["pgm_base64"]).startswith(b"P5\n")
    assert body["objects"][0]["label"] == "keys"
    # the robot key reads the export only, never the phone's routes
    assert on.get("/homes/flat/objects", headers={"Authorization": "Bearer robot"}).status_code == 401
    assert datetime.fromisoformat(body["generated_at"]).tzinfo == UTC


def test_the_owner_sees_each_rooms_map_without_robot_access_or_an_audit_entry(tmp_path):
    s = Settings(RECALL_DATA_DIR=tmp_path, RECALL_DEVICE_KEY="owner", RECALL_ROBOT_KEY="robot",
                 ROBOT_EXPORT_ENABLED=False, RECALL_TRACES="off")  # fmt: skip
    app = create_app(s)
    app.state.container.__dict__["export_for_robot"] = _exporter(tmp_path)[0]
    client = TestClient(app)
    owner = {"Authorization": "Bearer owner"}
    r = client.get("/homes/flat/room-map", params={"room": "Office"}, headers=owner)
    assert r.status_code == 200, r.text
    assert r.json()["room"] == "Office" and r.json()["objects"][0]["label"] == "keys"
    assert client.get("/homes/flat/room-map", params={"room": "Kitchen"}, headers=owner).status_code == 404
    # the robot key never reads it, and looking at your own map isn't robot activity
    assert client.get("/homes/flat/room-map", headers={"Authorization": "Bearer robot"}).status_code == 401
    assert not [e for e in client.get("/audit", headers=owner).json() if e["action"] == "robot_export.read"]


def test_a_rescan_updates_the_rooms_map_and_where_things_are(tmp_path):
    """Scan the room, move the box and the keys, scan it again: the room map is the rescan's."""
    import io

    def put_cloud(blobs, scan, points):
        buf = io.BytesIO()
        np.save(buf, points)
        blobs.put(f"{scan.folder}/episode/home_cloud.npy", buf.getvalue())

    r = Repos()
    blobs = MemoryBlobs()
    put_cloud(blobs, r.scan("s1", 10), room_points())  # the box at x 1.5..1.7
    r.ingest("s1", {"room": ROOM, "landmarks": [obj("desk", [1.0, 0.5, 0.38])],
                    "objects": [obj("keys", [1.0, 0.5, 0.8])]})  # fmt: skip
    moved = room_points()
    moved = moved[moved[:, 2] < 0.05]  # the box is gone from there...
    xs, ys, zs = np.meshgrid(np.arange(0.2, 0.4, 0.02), np.arange(0.4, 0.6, 0.02), np.arange(0.1, 0.5, 0.05))
    moved = np.vstack([moved, np.c_[xs.ravel(), ys.ravel(), zs.ravel()]])  # ...and stands at x 0.2..0.4 now
    put_cloud(blobs, r.scan("s2", 12, aligned_to="s1"), moved)
    r.ingest("s2", {"room": ROOM, "landmarks": [], "objects": [obj("keys", [1.5, 0.8, 0.8])]})

    s = Settings(RECALL_DATA_DIR=tmp_path, RECALL_DEVICE_KEY="owner", RECALL_TRACES="off")
    app = create_app(s)
    app.state.container.__dict__["export_for_robot"] = ExportForRobot(r.homes, r.scans, r.objects, blobs, FixedClock())
    body = TestClient(app).get("/homes/flat/room-map", params={"room": "Office"},
                               headers={"Authorization": "Bearer owner"}).json()  # fmt: skip
    assert body.get("scan_id") == "s2", body
    assert body["objects"][0]["position"] == [1.5, 0.8, 0.8]  # the keys where the rescan saw them
    m = body["map"]
    pgm = base64.b64decode(m["pgm_base64"])
    w, h = m["width"], m["height"]
    img = np.frombuffer(pgm.split(b"\n255\n", 1)[1], np.uint8).reshape(h, w)

    def shade(x, y):  # the image's top row is the map's highest y
        ox, oy = m["origin"][:2]
        return img[h - 1 - int((y - oy) / m["resolution"]), int((x - ox) / m["resolution"])]

    assert shade(0.3, 0.5) == 0  # occupied where the box stands now
    assert shade(1.6, 0.5) == 254  # free where it stood before


def test_a_damaged_line_in_the_walk_is_skipped(tmp_path):
    from recall_api.application import scan_geometry
    from recall_api.domain.memory import Scan, ScanStatus
    from tests.fakes import MemoryBlobs

    scan = Scan("s", "flat", "Office", ScanStatus.PROCESSED, 1, "x", 1, datetime(2026, 10, 30, tzinfo=UTC),
                transform_to_home=tuple(float(v) for v in np.eye(4).ravel()))  # fmt: skip
    pose = np.eye(4)
    pose[:3, 3] = [1.0, 2.0, 0.0]
    good = json.dumps({"pose": pose.T.ravel().tolist()})
    blobs = MemoryBlobs()
    blobs.put(f"{scan.folder}/episode/poses.jsonl", f"{good}\n{{}}\nnot json\n\n{good}\n".encode())
    assert scan_geometry.walked(blobs, scan).tolist() == [[1.0, 2.0], [1.0, 2.0]]
