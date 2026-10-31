"""The Verifier: SAM 3.1 + depth + geometry decide (the 30 cm rule); Muse Spark 1.1 may only downgrade; what the
camera saw updates memory."""

import numpy as np

from recall_api.application.plan_guidance import PlanGuidance
from recall_api.application.ports import Mask
from recall_api.application.verify_arrival import VerifyArrival
from recall_api.domain.spatial import CameraView, clock_and_distance, lift_box
from tests.fakes import FixedClock, MemoryBlobs
from tests.unit.test_guidance_compass import T
from tests.unit.test_matching_and_ingest import ROOM, Repos, obj

# keys in the home at (3.5, 1.5, 0.8) are at ARKit (3.5, -0.6, -1.5) in this scan's world (see test_guidance_compass)
CAMERA = np.eye(4)
CAMERA[:3, 3] = [3.5, -0.6, 0.0]  # 1.5 m in front of the keys, at their height, looking along -z


def view(depth_m=1.5) -> CameraView:
    return CameraView(CAMERA, 500.0, 500.0, 320.0, 240.0, (640, 480), np.full((48, 64), depth_m))


AHEAD = (300.0, 220.0, 340.0, 260.0)  # a box round the middle of the photo
RIGHT = (500.0, 220.0, 540.0, 260.0)  # 0.6 m to the right at 1.5 m


class Sam:
    def __init__(self, *masks):
        self.masks, self.prompts = list(masks), []

    def segment(self, jpeg, prompts):
        self.prompts += prompts
        return self.masks


class Spark:
    def __init__(self, answer):
        self.answer, self.asked = answer, 0

    def is_visible(self, label, jpeg):
        self.asked += 1
        return self.answer


def setup(sam, spark=None):
    r = Repos()
    r.scan("s1", 10)
    things = {"landmarks": [obj("desk", [3.5, 1.5, 0.38])], "objects": [obj("keys", [3.5, 1.5, 0.8])]}
    r.ingest("s1", {"room": ROOM, **things, "transform_to_home": T})
    keys = next(o for o in r.objects.items.values() if o.label == "keys")
    g = PlanGuidance(r.homes, r.scans, r.objects, MemoryBlobs(), lambda p: f"{p}1")
    sid = g.start("flat", keys.id, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1], "limited")["session_id"]
    n = iter(range(100))
    return VerifyArrival(g, r.objects, sam, spark, FixedClock(), lambda p: f"{p}{next(n)}"), sid, r, keys.id


def test_lifting_a_box_lands_on_the_thing_in_the_home():
    world = lift_box(view(), AHEAD)
    assert np.allclose(world, [3.5, -0.6, -1.5])
    home = (np.array(T, float).reshape(4, 4) @ np.append(world, 1))[:3]
    assert np.allclose(home, [3.5, 1.5, 0.8])
    assert lift_box(view(depth_m=0.0), AHEAD) is None  # no depth there: no guess
    cam_home = np.array(T, float).reshape(4, 4) @ CAMERA
    assert clock_and_distance(cam_home, home) == (12, 1.5)
    assert clock_and_distance(cam_home, home + [0.6, 0, 0])[0] == 1  # a little to the right


def test_seen_where_remembered_is_confirmed_and_refreshes_memory():
    verify, sid, r, oid = setup(Sam(Mask("keys", 0.9, None, AHEAD)))
    v = verify(sid, b"jpeg", view())
    assert v.outcome == "confirmed" and v.distance_cm == 0
    assert v.say == "Found it. Your keys are at 12 o'clock, 1.5 metres away."
    keys = r.objects.get(oid)
    assert len([o for o in keys.observations if keys.is_current(o)]) == 2  # a fresh sighting, same place


def test_seen_nearby_moves_it_in_memory():
    verify, sid, r, oid = setup(Sam(Mask("keys", 0.9, None, RIGHT)))
    v = verify(sid, b"jpeg", view())
    assert v.outcome == "found_nearby" and v.distance_cm == 60
    assert v.say == "Your keys are here, but moved: at 1 o'clock, 1.5 metres away. I've updated my memory."
    keys = r.objects.get(oid)
    assert np.allclose(keys.where().position.as_tuple(), [4.1, 1.5, 0.8])


def test_muse_spark_may_only_downgrade_and_only_when_sam_was_unsure():
    spark = Spark("no")
    verify, sid, r, oid = setup(Sam(Mask("keys", 0.6, None, AHEAD)), spark)
    assert verify(sid, b"jpeg", view()).outcome == "uncertain" and spark.asked == 1
    assert len(r.objects.get(oid).observations) == 1  # an unsure check changes nothing
    yes = Spark("yes")
    verify, sid, *_ = setup(Sam(Mask("keys", 0.6, None, AHEAD)), yes)
    assert verify(sid, b"jpeg", view()).outcome == "confirmed"
    sure = Spark("no")
    verify, sid, *_ = setup(Sam(Mask("keys", 0.9, None, AHEAD)), sure)
    assert verify(sid, b"jpeg", view()).outcome == "confirmed" and sure.asked == 0  # SAM was sure: not asked


def test_nothing_seen_or_only_a_hint():
    verify, sid, r, oid = setup(Sam())
    v = verify(sid, b"jpeg", view())
    assert v.outcome == "not_here" and "can't see your keys" in v.say
    verify, sid, *_ = setup(Sam(Mask("keys", 0.4, None, AHEAD)))
    assert verify(sid, b"jpeg", view()).outcome == "uncertain"
    far = (100.0, 220.0, 140.0, 260.0)  # seen, but over 2 m from where it was (depth 6 m would be far; use offset)
    verify, sid, *_ = setup(Sam(Mask("keys", 0.9, None, far)))
    v = verify(sid, b"jpeg", CameraView(CAMERA, 500.0, 500.0, 320.0, 240.0, (640, 480), np.full((48, 64), 5.0)))
    assert v.outcome == "uncertain" and "not where yours was" in v.say


def test_the_route_reads_the_frame_and_answers(tmp_path):
    import json

    from fastapi.testclient import TestClient

    from recall_api.config.settings import Settings
    from recall_api.infra.app import create_app

    verify, sid, *_ = setup(Sam(Mask("keys", 0.9, None, AHEAD)))
    app = create_app(Settings(RECALL_DATA_DIR=tmp_path, RECALL_DEVICE_KEY="k", RECALL_TRACES="off"))
    app.state.container.__dict__["verify_arrival"] = verify
    client = TestClient(app)
    pose = {"pose": CAMERA.T.ravel().tolist(), "intrinsics": {"fx": 500, "fy": 500, "cx": 320, "cy": 240},
            "image_size": [640, 480], "depth_size": [64, 48]}  # fmt: skip
    depth = np.full(48 * 64, 1500, "<u2").tobytes()
    files = {"image": ("a.jpg", b"jpeg", "image/jpeg"), "depth": ("d.bin", depth, "application/octet-stream")}
    r = client.post(f"/guidance/sessions/{sid}/verify", files=files, data={"pose": json.dumps(pose)},
                    headers={"Authorization": "Bearer k"})  # fmt: skip
    assert r.status_code == 200, r.text
    assert r.json()["outcome"] == "confirmed" and r.json()["say"].startswith("Found it.")
    files["depth"] = ("d.bin", depth[:100], "application/octet-stream")
    bad = client.post(f"/guidance/sessions/{sid}/verify", files=files, data={"pose": json.dumps(pose)},
                      headers={"Authorization": "Bearer k"})  # fmt: skip
    assert bad.status_code == 422
