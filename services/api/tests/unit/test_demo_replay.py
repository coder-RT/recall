"""`make demo`: the recorded sample is rebuilt through ingest and the Guide replays the recorded replies, no network."""

import json

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
        llm.chat([{"role": "system", "content": "x"}, {"role": "user", "content": "Where is my passport?"}], [])


def test_the_sample_holds_geometry_and_labels_only():
    result = json.loads((SAMPLE / "scan-result.json").read_text())
    assert set(result) == {"room", "landmarks", "objects", "transform_to_home"}
    for t in result["objects"] + result["landmarks"]:
        assert set(t) <= set(OBJECT_FIELDS)
    raw = {"scan_id": "x", "stats": {"path": "/Users/x"}, "room": {}, "landmarks": [], "transform_to_home": None,
           "objects": [{"label": "keys", "keyframe_index": 3, "note": "mine", "centroid": [0, 0, 0]}]}  # fmt: skip
    assert sanitise(raw)["objects"] == [{"label": "keys", "centroid": [0, 0, 0]}]
