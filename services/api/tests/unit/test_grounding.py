from recall_api.domain.assistant import check_grounding

TOOLS = [
    '{"label": "keys", "landmark": "hallway shelf", "shelf_level": 2, "height_band": "chest", "minutes_since_seen": 12}'
]
PLACES = {"hallway shelf", "kitchen counter", "desk"}


def test_an_answer_built_from_tool_output_is_grounded():
    r = check_grounding(
        "Your keys are on the hallway shelf, second level, chest height. Seen 12 minutes ago.", TOOLS, PLACES
    )
    assert r.ok


def test_a_place_no_tool_returned_is_caught():
    r = check_grounding("Your keys are on the kitchen counter.", TOOLS, PLACES)
    assert not r.ok and r.unsupported_places == ("kitchen counter",)


def test_a_made_up_number_is_caught():
    r = check_grounding("Your keys are 3 metres ahead.", TOOLS, PLACES)
    assert not r.ok and r.unsupported_numbers == ("3.0",)
