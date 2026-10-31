"""The Guide's grounding is enforced in code: a scripted model (test double) tries to invent a place."""

import json
from datetime import timedelta

from recall_api.application.ask_where_is import AskWhereIs
from recall_api.application.ports import ChatReply, ToolCall
from recall_api.application.tools import Tools
from recall_api.domain.memory import BBox, Home, Landmark, Observation, Position, TrackedObject
from tests.fakes import FixedClock, MemoryRepo


class ScriptedLlm:
    model = "scripted"

    def __init__(self, replies):
        self.replies = list(replies)

    def chat(self, messages, tools):
        return self.replies.pop(0)


def memory():
    homes, objects = MemoryRepo(), MemoryRepo()
    desk = Landmark(
        "lm1", "desk", BBox(Position(0, 0, 0), Position(1.2, 0.6, 0.76)), Position(0.6, 0.3, 0.38), room="Office"
    )
    homes.save(
        Home(
            "flat",
            "flat",
            landmarks=[
                desk,
                Landmark(
                    "lm2",
                    "kitchen counter",
                    BBox(Position(5, 5, 0), Position(6, 6, 0.9)),
                    Position(5.5, 5.5, 0.45),
                    room="Kitchen",
                ),
            ],
        )
    )
    keys = TrackedObject(
        "o1",
        "flat",
        "keys",
        observations=[
            Observation("ob1", "o1", "s1", FixedClock().now() - timedelta(minutes=12), Position(0.4, 0.3, 0.80), 0.9)
        ],
    )
    objects.save(keys)
    return homes, objects


def guide(replies):
    homes, objects = memory()
    return AskWhereIs(ScriptedLlm(replies), Tools(homes, objects, FixedClock()), [], homes)


FIND = ChatReply(None, [ToolCall("c1", "find_object", {"name": "keys"})])
DESCRIBE = ChatReply(None, [ToolCall("c2", "describe_location", {"object_id": "o1"})])


def test_a_grounded_answer_is_spoken_as_the_model_phrased_it():
    a = guide([FIND, DESCRIBE, ChatReply("Your keys are on the desk, at waist height. Seen 12 minutes ago.")])(
        "flat", "where are my keys?"
    )
    assert a.text.startswith("Your keys are on the desk") and a.tool_calls == 2 and a.object_id == "o1"


def test_an_invented_place_is_corrected_then_replaced_by_the_tool_facts():
    lie = ChatReply("Your keys are on the kitchen counter.")
    a = guide([FIND, DESCRIBE, lie, lie])("flat", "where are my keys?")
    assert "kitchen" not in a.text and "on the desk" in a.text and "12 minutes ago" in a.text


def test_not_found_says_so_and_suggests_scanning():
    a = guide(
        [ChatReply(None, [ToolCall("c1", "find_object", {"name": "passport"})]), ChatReply("ok"), ChatReply("ok")]
    )("flat", "where is my passport?")
    assert "haven't seen" in a.text


def test_find_object_says_where_so_one_tool_call_answers():
    a = guide([FIND, ChatReply("Your keys are on the desk in the Office, at waist height, seen 12 minutes ago.")])(
        "flat", "where are my keys?"
    )
    assert a.tool_calls == 1 and a.grounded and a.text.startswith("Your keys are on the desk")
    homes, objects = memory()
    from recall_api.application.tools import ToolContext

    (match,) = Tools(homes, objects, FixedClock()).find_object(ToolContext("flat"), "keys")["matches"]
    assert (match["room"], match["landmark"], match["relation"], match["height_band"]) == (
        "Office",
        "desk",
        "on",
        "waist",
    )


def test_the_fallback_needs_only_find_object():
    lie = ChatReply("Your keys are on the kitchen counter.")
    a = guide([FIND, lie, lie])("flat", "where are my keys?")
    assert a.text.startswith("Your keys are on the desk") and "kitchen" not in a.text


def test_the_fallback_names_the_newest_of_several_matches():
    from recall_api.application.ask_where_is import fallback_sentence

    out = json.dumps({"result": "found", "matches": [
        {"label": "bag", "color": "grey", "landmark": "desk", "relation": "near", "height_band": "knee",
         "seen_when": "today at 10:00"},
        {"label": "bag", "color": "white", "landmark": "cabinet", "relation": "on", "height_band": "waist"},
    ]})  # fmt: skip
    assert fallback_sentence([out]) == "Your grey bag is near the desk, at knee height, seen today at 10:00."
