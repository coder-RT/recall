"""The privacy note's facts follow the settings: what leaves the Mac, to whom, and only what is true now."""

from fastapi.testclient import TestClient

from recall_api.application.describe_privacy import describe_privacy
from recall_api.config.settings import Settings
from recall_api.infra.app import create_app


def test_scan_photos_voice_and_arrival_photos_go_to_metas_api_and_say_so():
    f = describe_privacy("baseten_spark_open", "baseten_spark_open", "local", False, 90)
    to = {x.what.split(" (")[0].split(",")[0]: x.to for x in f.sent}
    assert to["Scan photos"] == "Meta Model API: SAM 3.1"
    assert to["Your spoken question"] == "Meta Model API: Muse Voice Transcribe"
    assert to["Your question as text"] == "Baseten: Muse Spark Open"
    assert f.stored_on == "This Mac" and not any("robot" in x.to.lower() for x in f.sent)


def test_private_mode_keeps_the_question_on_the_mac():
    f = describe_privacy("lmstudio", "lmstudio", "local", False, 90)
    question = next(x for x in f.sent if x.what.startswith("Your question as text"))
    assert question.on_this_mac and "this Mac" in question.to


def test_robot_rows_only_while_robot_access_is_on():
    f = describe_privacy("baseten_spark_open", "baseten_spark_open", "local", True, 90)
    robot = [x for x in f.sent if "robot" in x.when.lower()]
    assert len(robot) == 2 and "no photos" in robot[0].what


def test_over_http_owner_only(tmp_path):
    s = Settings(RECALL_DATA_DIR=tmp_path, RECALL_DEVICE_KEY="owner", RECALL_ROBOT_KEY="robot", RECALL_TRACES="off")
    c = TestClient(create_app(s))
    assert c.get("/privacy", headers={"Authorization": "Bearer robot"}).status_code == 401
    body = c.get("/privacy", headers={"Authorization": "Bearer owner"}).json()
    assert body["stored_on"] == "This Mac" and body["robot_access"] is False and body["audit_days"] == 90
    assert len(body["sent"]) == 4
