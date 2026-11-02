"""The user's fixes after a scan: they win over measurements, survive later scans, and tell look-alikes apart."""

from datetime import UTC, datetime

import pytest

from recall_api.application.correct_object import CorrectionError, CorrectionInput, CorrectObject
from recall_api.application.tools import ToolContext, Tools
from recall_api.domain.memory import Observation, Position, TrackedObject
from tests.fakes import FixedClock, MemoryRepo

T = datetime(2026, 10, 30, 11, 0, tzinfo=UTC)


def _fixer(objects, homes=None) -> CorrectObject:
    return CorrectObject(objects, homes or MemoryRepo(), FixedClock(), lambda prefix: f"{prefix}_1")


def _bag(oid: str, color: str, conf: float = 0.6, z: float = 0.4) -> TrackedObject:
    o = TrackedObject(oid, "flat", "bag", color=color, size_m=(0.4, 0.2, 0.5))
    o.observations.append(Observation(f"obs_{oid}", oid, "s1", T, Position(1.0, 1.0, z), conf))
    return o


def test_colour_tells_two_bags_apart():
    red, blue = _bag("obj_1", "red"), _bag("obj_2", "blue")
    assert red.matches("red bag") and not blue.matches("red bag")
    assert red.matches("bag") and blue.matches("bags")


def test_users_colour_and_name_win():
    repo = MemoryRepo()
    repo.save(_bag("obj_1", "black"))
    obj = _fixer(repo).update("flat", "obj_1", CorrectionInput(color="Blue", name="work bag"))
    assert obj.display_color() == "blue" and obj.matches("blue bag") and obj.matches("work bag")


def test_users_height_replaces_the_measured_one_and_confirm_makes_it_certain():
    repo = MemoryRepo()
    repo.save(_bag("obj_1", "red", conf=0.3, z=0.4))
    assert repo.get("obj_1").where() is None  # too unsure to answer with
    obj = _fixer(repo).update("flat", "obj_1", CorrectionInput(height_m=0.75, confirmed=True))
    where = obj.where()
    assert where.position.z == 0.75 and where.confidence == 1.0
    assert obj.observations[0].position.z == 0.4  # what the scan measured stays on record


def test_null_clears_a_correction():
    repo = MemoryRepo()
    repo.save(_bag("obj_1", "red"))
    fix = _fixer(repo)
    fix.update("flat", "obj_1", CorrectionInput(height_m=1.0))
    assert fix.update("flat", "obj_1", CorrectionInput(height_m=None)).where().position.z == 0.4


@pytest.mark.parametrize(
    "change,code",
    [(CorrectionInput(color="teal"), "bad_color"), (CorrectionInput(height_m=4.0), "bad_height"),
     (CorrectionInput(note="x" * 201), "too_long")],
)  # fmt: skip
def test_bad_values_are_refused(change, code):
    repo = MemoryRepo()
    repo.save(_bag("obj_1", "red"))
    with pytest.raises(CorrectionError) as e:
        _fixer(repo).update("flat", "obj_1", change)
    assert e.value.code == code


def test_remove_and_other_homes():
    repo = MemoryRepo()
    repo.save(_bag("obj_1", "red"))
    with pytest.raises(CorrectionError):
        _fixer(repo).remove("other-home", "obj_1")
    _fixer(repo).remove("flat", "obj_1")
    assert repo.get("obj_1") is None


def test_tools_report_colour_name_and_what_the_user_set():
    objects = MemoryRepo()
    objects.save(_bag("obj_1", "red"))
    _fixer(objects).update("flat", "obj_1", CorrectionInput(name="gym bag", note="zip is broken"))
    tools = Tools(MemoryRepo(), objects, FixedClock())
    found = tools.find_object(ToolContext("flat"), "red bag")
    assert found["matches"][0]["name"] == "gym bag" and found["matches"][0]["color"] == "red"
