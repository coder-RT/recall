"""Where am I? A photo matched against the scans' place indexes: the room, the pose in the map's world, the hint."""

import json

import cv2
import numpy as np
import pytest

from recall_api.adapters.outbound.vision.orb_place_matcher import OrbPlaceMatcher
from recall_api.application.locate_by_photo import LocateByPhoto, LocateError, hints, index_key
from recall_api.application.ports import PlaceMatch, PlaceQuery
from recall_api.domain.memory import BBox, Landmark, Position, ScanStatus
from tests.unit.test_matching_and_ingest import Repos

POSE = tuple(float(v) for v in np.eye(4).reshape(-1))
Q = PlaceQuery(b"jpeg", 700.0, 700.0, 512.0, 384.0)


class FakeMatcher:
    def __init__(self, inliers: dict[str, int]):
        self.inliers, self.asked = inliers, {}

    def match(self, query, candidates, budget_s=0.4):
        self.asked = candidates
        out = [PlaceMatch(s, n, POSE if n >= 6 else None, 1.5, 0) for s, n in self.inliers.items() if s in candidates]
        return sorted(out, key=lambda m: -m.inliers)


def _home(inliers):
    r = Repos()
    for sid, hour, room, aligned in [
        ("o1", 9, "Office", None),
        ("o2", 11, "Office", "o1"),
        ("b1", 10, "Bedroom", None),
    ]:
        s = r.scan(sid, hour, room=room, aligned_to=aligned)
        s.status = ScanStatus.PROCESSED
        r.scans.save(s)
    home = r.homes.get("flat")
    box = lambda lo, hi: BBox(Position(*lo), Position(*hi))  # noqa: E731
    home.landmarks = [
        Landmark("l1", "chair", box((0, 0, 0), (0.5, 0.5, 0.9)), Position(0.2, 0.2, 0.4), room="Office"),
        Landmark("l2", "chair", box((1, 0, 0), (1.5, 0.5, 0.9)), Position(1.2, 0.2, 0.4), room="Office"),
        Landmark("l3", "tv", box((2, 0, 1), (3, 0.1, 1.6)), Position(2.5, 0.05, 1.3), room="Office"),
        Landmark("l4", "bed", box((0, 0, 0), (2, 1.6, 0.5)), Position(1, 0.8, 0.25), room="Bedroom"),
    ]
    r.homes.save(home)
    m = FakeMatcher(inliers)
    return LocateByPhoto(r.homes, r.scans, m), m, r


def test_in_the_maps_room_the_pose_comes_back_and_the_whole_family_is_tried():
    use, m, r = _home({"o1": 20, "o2": 64, "b1": 9})
    fix = use("flat", "o2", Q, room="Office")
    assert (fix.room, fix.pose, fix.inliers, fix.scan_id) == ("Office", POSE, 64, "o2")
    assert set(m.asked) == {"o1", "o2", "b1"}  # the map's family (same world) and the other room's newest scan
    assert m.asked["b1"] == index_key(r.scans.get("b1")) and m.asked["b1"].endswith("/episode/place_index.npz")
    assert fix.hint[0] == "tv" and "chair" in fix.hint  # one of a kind first


def test_in_another_room_it_says_so_and_gives_no_pose():
    fix, *_ = _home({"o1": 12, "o2": 10, "b1": 80})
    f = fix("flat", "o1", Q, room="Office")
    assert (f.room, f.pose, f.runner_up_room) == ("Bedroom", None, "Office")
    assert f.hint == ["bed"]  # what to point at where the phone is


def test_two_rooms_alike_name_neither_and_give_no_pose():
    use, *_ = _home({"o1": 40, "b1": 35})
    f = use("flat", "o1", Q)
    assert f.room is None and f.pose is None


def test_too_few_inliers_give_no_pose():
    use, *_ = _home({"o1": 25})
    assert use("flat", "o1", Q).pose is None


def test_a_scan_of_another_home_is_refused():
    use, *_ = _home({})
    with pytest.raises(LocateError):
        use("elsewhere", "o1", Q)


def test_hints_skip_doors_and_repeat_kinds():
    box = BBox(Position(0, 0, 0), Position(1, 1, 1))
    lms = [Landmark(str(i), lab, box, Position(0, 0, 0)) for i, lab in enumerate(["door", "chair", "chair", "sofa"])]
    assert hints(lms) == ["sofa", "chair"]


# The real matcher on a synthetic scene: a textured wall 2 m in front of the camera.
FX, CX, CY, W, H, Z = 700.0, 512.0, 384.0, 1024, 768, 2.0


def _wall(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    img = np.full((H, W), 128, np.uint8)
    for _ in range(400):
        x, y = int(rng.integers(0, W)), int(rng.integers(0, H))
        if rng.random() < 0.5:
            cv2.circle(img, (x, y), int(rng.integers(4, 30)), int(rng.integers(0, 255)), -1)
        else:
            cv2.rectangle(
                img, (x, y), (x + int(rng.integers(5, 40)), y + int(rng.integers(5, 40))), int(rng.integers(0, 255)), -1
            )
    return img


def _index(tmp_path, img) -> str:
    """The pipeline's index for one keyframe: ORB (same settings) lifted onto the wall, camera at the ARKit origin."""
    orb = cv2.ORB_create(nfeatures=1000, scaleFactor=1.2, nlevels=8, fastThreshold=12)
    s = 640 / W
    kps, desc = orb.detectAndCompute(cv2.resize(img, (640, 480), interpolation=cv2.INTER_AREA), None)
    uv = np.array([k.pt for k in kps]) / s
    cam = np.c_[(uv[:, 0] - CX) / FX * Z, (uv[:, 1] - CY) / FX * Z, np.full(len(uv), Z)]
    world = cam * [1, -1, -1]  # OpenCV camera -> ARKit world (identity ARKit pose)
    path = tmp_path / "place_index.npz"
    np.savez(path, format=np.array("recall-place-index/1"), desc=desc, xyz=world.astype(np.float32),
             frame=np.zeros(len(desc), np.int32), frame_ids=np.array([0], np.int32),
             poses=np.eye(4, dtype=np.float32).reshape(1, 16), image_size=np.array([W, H], np.int32))  # fmt: skip
    return str(path)


class Disk:
    def local_path(self, key):
        return key


def _jpeg(img) -> bytes:
    return cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 90])[1].tobytes()


def test_the_matcher_finds_how_far_the_camera_moved(tmp_path):
    wall = _wall(1)
    key = _index(tmp_path, wall)
    # the camera 10 cm to its right: the wall moves 35 px to the left in the photo
    dx = FX * 0.10 / Z
    moved = cv2.warpAffine(wall, np.float32([[1, 0, -dx], [0, 1, 0]]), (W, H), borderValue=128)
    m = OrbPlaceMatcher(Disk()).match(PlaceQuery(_jpeg(moved), FX, FX, CX, CY), {"s": key})[0]
    assert m.inliers >= 30 and m.reproj_px < 2
    T = np.array(m.pose).reshape(4, 4).T  # column-major -> matrix; ARKit camera-to-world
    assert np.allclose(T[:3, 3], [0.10, 0, 0], atol=0.02)  # ARKit +x is the camera's right
    assert np.allclose(T[:3, :3], np.eye(3), atol=0.02)


def test_a_photo_of_somewhere_else_gives_no_pose(tmp_path):
    key = _index(tmp_path, _wall(1))
    m = OrbPlaceMatcher(Disk()).match(PlaceQuery(_jpeg(_wall(2)), FX, FX, CX, CY), {"s": key})
    assert not m or m[0].pose is None or m[0].inliers < 30


def test_the_route_maps_the_form_and_refuses_a_bad_pose(tmp_path):
    from fastapi.testclient import TestClient

    from recall_api.config.settings import Settings
    from recall_api.infra.app import create_app

    use, m, _ = _home({"o1": 50})
    app = create_app(Settings(RECALL_DATA_DIR=tmp_path, RECALL_DEVICE_KEY="k", RECALL_TRACES="off"))
    app.state.container.__dict__["locate_by_photo"] = use
    client = TestClient(app)
    pose = {"pose": list(POSE), "intrinsics": {"fx": 700, "fy": 700, "cx": 512, "cy": 384}, "image_size": [1024, 768]}
    files = {"image": ("a.jpg", b"jpeg", "image/jpeg")}
    auth = {"Authorization": "Bearer k"}
    r = client.post("/homes/flat/locate", files=files, data={"pose": json.dumps(pose), "scan_id": "o1"}, headers=auth)
    assert r.status_code == 200, r.text
    assert r.json()["room"] == "Office" and len(r.json()["pose"]) == 16 and r.json()["hint"][0] == "tv"
    bad = client.post("/homes/flat/locate", files=files, data={"pose": "{}", "scan_id": "o1"}, headers=auth)
    assert bad.status_code == 422
    gone = client.post(
        "/homes/flat/locate", files=files, data={"pose": json.dumps(pose), "scan_id": "zz"}, headers=auth
    )
    assert gone.status_code == 404
