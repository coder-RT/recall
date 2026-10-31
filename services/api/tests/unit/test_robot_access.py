"""Robot access: off by default; the owner turns it on from the phone, which opens the robot export and the Home
Memory agent; a robot's own key can't turn it on; it survives a restart."""

from fastapi.testclient import TestClient

from recall_api.config.settings import Settings
from recall_api.infra.app import create_app
from tests.unit.test_robot_export import _exporter

OWNER = {"Authorization": "Bearer owner"}
ROBOT = {"Authorization": "Bearer robot"}


def _client(tmp_path) -> TestClient:
    s = Settings(RECALL_DATA_DIR=tmp_path, RECALL_DEVICE_KEY="owner", RECALL_ROBOT_KEY="robot",
                 RECALL_PUBLIC_URL="http://mac.local:8000", RECALL_TRACES="off")  # fmt: skip
    app = create_app(s)
    app.state.container.__dict__["export_for_robot"] = _exporter(tmp_path)[0]
    return TestClient(app)


def test_off_by_default_and_the_owner_turns_it_on(tmp_path):
    c = _client(tmp_path)
    s = c.get("/sharing", headers=OWNER).json()
    assert s == {"robot_access": False, "a2a_url": "http://mac.local:8000/a2a/home-memory",
                 "agent_card_url": "http://mac.local:8000/a2a/home-memory/.well-known/agent-card.json",
                 "export_url": "http://mac.local:8000/homes/flat/robot-export"}  # fmt: skip
    assert c.get("/homes/flat/robot-export", headers=ROBOT).status_code == 403
    assert c.get("/homes/flat/robot-export", headers=OWNER).status_code == 200  # the owner can always export it
    assert c.get("/a2a/home-memory/.well-known/agent-card.json").status_code == 404
    assert c.put("/sharing", json={"robot_access": True}, headers=OWNER).json()["robot_access"] is True
    assert c.get("/homes/flat/robot-export", headers=ROBOT).status_code == 200
    assert c.get("/a2a/home-memory/.well-known/agent-card.json").status_code == 200
    assert c.put("/sharing", json={"robot_access": False}, headers=OWNER).json()["robot_access"] is False
    assert c.get("/homes/flat/robot-export", headers=ROBOT).status_code == 403


def test_a_robot_cannot_turn_itself_on(tmp_path):
    c = _client(tmp_path)
    assert c.put("/sharing", json={"robot_access": True}, headers=ROBOT).status_code == 401
    assert c.get("/sharing", headers=ROBOT).status_code == 401
    assert c.get("/sharing", headers=OWNER).json()["robot_access"] is False


def test_it_is_kept_on_the_mac(tmp_path):
    _client(tmp_path).put("/sharing", json={"robot_access": True}, headers=OWNER)
    assert _client(tmp_path).get("/sharing", headers=OWNER).json()["robot_access"] is True  # a new app, same data
