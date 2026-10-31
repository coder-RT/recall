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
