import json

from recall_api.application.tools import TOOL_NAMES
from recall_api.infra.db import API_ROOT


def test_tools_json_matches_the_registry():
    tools = json.loads((API_ROOT / "resources" / "tools.json").read_text())
    assert tuple(t["function"]["name"] for t in tools) == TOOL_NAMES
