"""The recorded demo's model and clock, and what /ask tells the caller when a model can't answer."""

import json
from datetime import UTC, datetime

import httpx
from fastapi.testclient import TestClient

from recall_api.adapters.outbound.replay.recorded_llm import NotRecorded, RecordedLlm, RecordingLlm
from recall_api.application.ports import ChatReply, ToolCall
from recall_api.config.settings import Settings
from recall_api.infra.app import create_app
from recall_api.infra.clock import FrozenClock

Q = [{"role": "system", "content": "s"}, {"role": "user", "content": "Where are my keys?"}]
AFTER_TOOL = Q + [{"role": "assistant", "content": ""}, {"role": "tool", "content": "{}"}]


class Scripted:
    model = "real"

    def __init__(self, replies):
        self.replies = list(replies)

    def chat(self, messages, tools):
        return self.replies.pop(0)


def test_recording_then_replaying_gives_the_same_replies_step_by_step(tmp_path):
    first = ChatReply(None, [ToolCall("c1", "find_object", {"name": "keys"})])
    second = ChatReply("Your keys are on the desk.")
    rec = RecordingLlm(Scripted([first, second]))
    assert rec.chat(Q, []) is first and rec.chat(AFTER_TOOL, []) is second and rec.model == "real"
    path = tmp_path / "guide.jsonl"
    path.write_text("".join(json.dumps(line) + "\n" for line in rec.lines))
    replay = RecordedLlm(path)
    a, b = replay.chat(Q, []), replay.chat(AFTER_TOOL, [])
    assert (a.tool_calls[0].name, a.tool_calls[0].arguments) == ("find_object", {"name": "keys"})
    assert b.text == "Your keys are on the desk." and b.model == replay.model == "replay:muse-spark-open (recorded)"
    assert replay.questions == ["Where are my keys?"]


def test_a_step_that_was_not_recorded_is_not_guessed(tmp_path):
    path = tmp_path / "guide.jsonl"
    path.write_text(json.dumps({"question": "Where are my keys?", "step": 0, "reply": {"text": "x", "tool_calls": []}}))
    replay = RecordedLlm(path)
    try:
        replay.chat(AFTER_TOOL + [{"role": "assistant", "content": ""}], [])
    except NotRecorded as e:
        assert "Where are my keys?" in str(e)
    else:
        raise AssertionError("an unrecorded step must not be answered")


def test_the_frozen_clock_is_utc_even_from_a_naive_time():
    assert FrozenClock(datetime(2026, 10, 31, 18, 21)).now() == datetime(2026, 10, 31, 18, 21, tzinfo=UTC)


class Broken:
    model = "broken"

    def __init__(self, error):
        self.error = error

    def chat(self, messages, tools):
        raise self.error


def test_ask_shows_a_models_own_message_but_hides_other_errors(tmp_path):
    app = create_app(Settings(RECALL_DATA_DIR=tmp_path, RECALL_DEVICE_KEY="k", RECALL_TRACES="off"))
    c, http = app.state.container, TestClient(app)
    body = {"home_id": "flat", "question": "Where are my keys?"}
    c.__dict__["llm"] = Broken(NotRecorded("This question isn't in the recorded demo. Try: Where are my keys?"))
    c.__dict__.pop("ask", None)
    r = http.post("/ask", json=body, headers={"Authorization": "Bearer k"})
    assert r.status_code == 503 and r.json()["detail"].startswith("This question isn't in the recorded demo")
    c.__dict__["llm"] = Broken(httpx.ConnectError("secret-host.internal:1234 refused"))
    c.__dict__.pop("ask", None)
    r = http.post("/ask", json=body, headers={"Authorization": "Bearer k"})
    assert r.status_code == 503 and "secret-host" not in r.text and "ConnectError" in r.text
