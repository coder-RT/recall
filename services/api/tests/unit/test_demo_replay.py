"""`make demo`: the recorded sample is rebuilt through ingest and the Guide replays the recorded replies, no network."""

import json

import numpy as np
import pytest

from recall_api.adapters.outbound.replay.recorded_llm import NotRecorded, RecordedLlm
from recall_api.infra.demo import HOME, OBJECT_FIELDS, SAMPLE, build, replay_settings, sanitise

pytestmark = pytest.mark.skipif(not (SAMPLE / "meta.json").exists(), reason="no recorded sample")


def test_the_demo_gives_the_recorded_answers_without_any_model(tmp_path):
    meta = json.loads((SAMPLE / "meta.json").read_text())
    c = build(replay_settings(tmp_path, SAMPLE), SAMPLE)
    assert c.llm.model == "replay:muse-spark-open (recorded)"
    for rec in meta["answers"]:
        a = c.ask(HOME, rec["question"])
        assert (a.text, a.tool_calls) == (rec["answer"], rec["tool_calls"]), rec["question"]
        assert a.model.startswith("replay:")


def test_an_unrecorded_question_says_so_and_lists_the_recorded_ones():
    llm = RecordedLlm(SAMPLE / "guide.jsonl")
    with pytest.raises(NotRecorded, match="Where are my keys"):
        llm.chat([{"role": "system", "content": "x"}, {"role": "user", "content": "Where is my scarf?"}], [])


def test_the_sample_holds_geometry_and_labels_only():
    result = json.loads((SAMPLE / "scan-result.json").read_text())
    assert set(result) == {"room", "landmarks", "objects", "transform_to_home"}
    for t in result["objects"] + result["landmarks"]:
        assert set(t) <= set(OBJECT_FIELDS)
    raw = {"scan_id": "x", "stats": {"path": "/Users/x"}, "room": {}, "landmarks": [], "transform_to_home": None,
           "objects": [{"label": "keys", "keyframe_index": 3, "note": "mine", "centroid": [0, 0, 0]}]}  # fmt: skip
    assert sanitise(raw)["objects"] == [{"label": "keys", "centroid": [0, 0, 0]}]


def test_the_sample_geometry_is_positions_only():
    from recall_api.infra.demo import thin_cloud, walk_poses

    for line in (SAMPLE / "poses.jsonl").read_text().splitlines():
        assert set(json.loads(line)) == {"pose"}  # no times, compass readings or tracking notes
    cloud = np.load(SAMPLE / "home_cloud.npy")
    assert cloud.ndim == 2 and cloud.shape[1] == 3  # x, y, z only: no colours
    assert len(thin_cloud(np.array([[0, 0, 0], [0.01, 0.01, 0.01], [1, 1, 1]]))) == 2
    raw = '{"t": 1, "heading": {"magnetic_deg": 3}, "pose": [1, 0]}\nnot json\n'
    assert walk_poses(raw) == '{"pose": [1.0, 0.0]}\n'


def test_the_demo_routes_each_answer_from_where_the_scan_began(tmp_path):
    from recall_api.infra.demo import walks

    result = json.loads((SAMPLE / "scan-result.json").read_text())
    shift = (1.0, -2.0)  # a viewer export centred elsewhere
    viewer = [{"label": o["label"], "at": [o["centroid"][0] - shift[0], o["centroid"][1] - shift[1], 0]}
              for o in result["objects"]]  # fmt: skip
    (tmp_path / "meta.json").write_text(json.dumps({"objects": viewer}))
    out = walks(SAMPLE, tmp_path / "meta.json")
    keys = next(w for w in out["walks"] if w["question"] == "Where are my keys?")
    assert keys["mode"] == "route" and keys["steps"] and keys["label"] == "keys"
    assert all(set(s) == {"clock", "metres", "say"} for s in keys["steps"])
    # the route ends at the keys, in the viewer's frame
    assert np.hypot(keys["path"][-1][0] - keys["target"][0], keys["path"][-1][1] - keys["target"][1]) < 0.8
    unseen = next(w for w in out["walks"] if "umbrella" in w["question"])
    assert "path" not in unseen  # nothing to walk to: the answer alone


def test_a_viewer_export_of_another_scan_is_refused():
    from recall_api.infra.demo import viewer_shift

    ours = [{"label": l, "centroid": [i, 0, 0]} for i, l in enumerate(("keys", "mug", "book", "bag"))]  # noqa: E741
    other = [{"label": l, "at": [i * 2.0, 0, 0]} for i, l in enumerate(("keys", "mug", "book", "bag"))]  # noqa: E741
    with pytest.raises(ValueError, match="not this scan"):
        viewer_shift(ours, other)


def test_every_question_that_names_a_thing_walks_there_or_offers_the_choices(tmp_path):
    from recall_api.infra.demo import walks

    result = json.loads((SAMPLE / "scan-result.json").read_text())
    viewer = [{"label": o["label"], "at": o["centroid"]} for o in result["objects"]]
    (tmp_path / "meta.json").write_text(json.dumps({"objects": viewer}))
    out = {w["question"]: w for w in walks(SAMPLE, tmp_path / "meta.json")["walks"]}
    for q, w in out.items():
        if "umbrella" in q:
            assert "path" not in w and "choices" not in w  # never seen: nothing to walk to
            continue
        options = w.get("choices") or [w]
        assert all(o["steps"] and o["arrive"] for o in options), q
    # "which one?": each laptop has its own route, ending at its own laptop
    laptops = out["Where is my laptop?"]["choices"]
    assert len(laptops) == 2 and laptops[0]["target"] != laptops[1]["target"]
    for c in laptops:
        end = c["path"][-1]
        assert np.hypot(end[0] - c["target"][0], end[1] - c["target"][1]) < 0.8
        assert c["place"].endswith("height")  # from the tool's fields, e.g. "near the table · waist height"
