from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

from recall_api.application.ask_where_is import fallback_sentence
from recall_api.domain.assistant import is_plural, spoken_when

WARSAW = ZoneInfo("Europe/Warsaw")
NOW = datetime(2026, 10, 31, 10, 0, tzinfo=UTC)  # 11:00 in Warsaw (CET since 25 Oct)


def ago(**kw) -> str:
    return spoken_when(NOW - timedelta(**kw), NOW, WARSAW)


def test_recent_sightings_say_how_long_ago():
    assert ago(seconds=20) == "just now"
    assert ago(minutes=1) == "1 minute ago"
    assert ago(minutes=12) == "12 minutes ago"
    assert ago(minutes=70) == "about 1 hour ago"
    assert ago(hours=7, minutes=20) == "about 7 hours ago"


def test_older_sightings_name_the_day_in_local_time():
    # 03:21 UTC on 30 October is 04:21 in Warsaw: the bare UTC hour was what confused people
    assert spoken_when(datetime(2026, 10, 30, 3, 21, tzinfo=UTC), NOW, WARSAW) == "yesterday at 04:21"
    assert spoken_when(datetime(2026, 10, 27, 18, 5, tzinfo=UTC), NOW, WARSAW) == "on Tuesday at 19:05"
    assert spoken_when(datetime(2026, 10, 20, 9, 0, tzinfo=UTC), NOW, WARSAW) == "on 20 October"


def test_local_midnight_decides_the_day():
    just_after = datetime(2026, 10, 29, 23, 30, tzinfo=UTC)  # 00:30 on the 30th in Warsaw (still the 29th in UTC)
    assert spoken_when(just_after, datetime(2026, 10, 31, 22, 45, tzinfo=UTC), WARSAW) == "yesterday at 00:30"
    just_before = datetime(2026, 10, 30, 22, 30, tzinfo=UTC)  # 23:30 on the 30th; asked at 00:30 on 1 November
    assert spoken_when(just_before, datetime(2026, 10, 31, 23, 30, tzinfo=UTC), WARSAW) == "on Friday at 23:30"


def test_summer_time_is_used_before_the_change():
    # 24 October was still CEST (UTC+2)
    assert spoken_when(datetime(2026, 10, 24, 6, 0, tzinfo=UTC), NOW, WARSAW) == "on 24 October"
    assert spoken_when(datetime(2026, 10, 26, 6, 0, tzinfo=UTC), NOW, WARSAW) == "on Monday at 07:00"


def test_plurals():
    assert is_plural("keys") and is_plural("headphones") and is_plural("reading glasses")
    assert not is_plural("glass") and not is_plural("bus") and not is_plural("mug")


def test_fallback_says_the_day_and_agrees():
    facts = (
        '{"label": "keys", "color": "beige", "landmark": "desk", "relation": "near", "height_band": "waist",'
        ' "seen_when": "yesterday at 04:21"}'
    )
    assert fallback_sentence([facts]) == "Your beige keys are near the desk, at waist height, seen yesterday at 04:21."
    mug = (
        '{"label": "mug", "landmark": "desk", "relation": "on", "height_band": "waist", "seen_when": "12 minutes ago"}'  # noqa: E501
    )
    assert fallback_sentence([mug]) == "Your mug is on the desk, at waist height, seen 12 minutes ago."


def test_the_tools_return_seen_when_in_the_homes_time_zone():
    """The tools the Guide calls carry the spoken time, so the model never has to turn a UTC hour into words."""
    import json

    from recall_api.application.tools import ToolContext, Tools
    from recall_api.domain.memory import Observation, Position, TrackedObject
    from tests.fakes import FixedClock
    from tests.unit.test_ask_where_is import memory

    homes, objects = memory()
    # 03:21 UTC the day before the clock's "now" (12:00 UTC on 30 October): 04:21 in Warsaw
    seen = datetime(2026, 10, 29, 3, 21, tzinfo=UTC)
    objects.save(
        TrackedObject(
            "o2", "flat", "wallet", observations=[Observation("ob2", "o2", "s1", seen, Position(0.5, 0.3, 0.8), 0.9)]
        )
    )
    tools = Tools(homes, objects, FixedClock(), tz=WARSAW)
    ctx = ToolContext(home_id="flat")

    found = json.loads(tools.run(ctx, "find_object", {"name": "wallet"}))
    assert found["matches"][0]["seen_when"] == "yesterday at 04:21"
    described = json.loads(tools.run(ctx, "describe_location", {"object_id": "o2"}))
    assert described["seen_when"] == "yesterday at 04:21"
    assert "seen_at" not in described  # the bare hour is gone
    keys = json.loads(tools.run(ctx, "describe_location", {"object_id": "o1"}))
    assert keys["seen_when"] == "12 minutes ago"
    # the answer built from those tool outputs alone
    assert (
        fallback_sentence(ctx.outputs[-2:-1]) == "Your wallet is on the desk, at waist height, seen yesterday at 04:21."
    )


def test_a_spoken_time_passes_the_grounding_check():
    """Every number in "yesterday at 04:21" comes from the tool output, so a correct answer isn't rejected."""
    from recall_api.domain.assistant import check_grounding

    tool = '{"label": "keys", "landmark": "desk", "seen_when": "yesterday at 04:21"}'
    assert check_grounding("Your keys are near the desk, seen yesterday at 04:21.", [tool], {"desk"}).ok
    assert not check_grounding("Your keys are near the desk, seen yesterday at 03:21.", [tool], {"desk"}).ok
