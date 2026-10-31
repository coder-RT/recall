"""Every path in the bundled spec is served, and the app serves no undocumented route."""

import json

from recall_api.config.settings import Settings
from recall_api.infra.app import create_app
from recall_api.infra.db import API_ROOT


def test_spec_and_app_have_the_same_routes(tmp_path):
    spec = json.loads((API_ROOT / "build" / "openapi.json").read_text())
    documented = {
        (m.upper(), p)
        for p, ops in spec["paths"].items()
        for m in ops
        if m in {"get", "post", "put", "patch", "delete"}
    }
    app = create_app(Settings(RECALL_DATA_DIR=tmp_path, RECALL_TRACES="off"))

    def walk(routes):  # FastAPI wraps each included router; look inside
        for r in routes:
            inner = getattr(r, "original_router", None)
            yield from walk(inner.routes) if inner is not None else [r]

    served = {
        (m, r.path) for r in walk(app.routes) if getattr(r, "include_in_schema", False) for m in r.methods - {"HEAD"}
    }
    assert documented == served


def test_tools_json_has_the_five_tools():
    tools = json.loads((API_ROOT / "resources" / "tools.json").read_text())
    assert [t["function"]["name"] for t in tools] == [
        "find_object", "describe_location", "localize", "plan_route", "explain"
    ]  # fmt: skip
