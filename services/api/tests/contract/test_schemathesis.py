"""The served API against its own spec, with generated requests (Schemathesis): every GET answers without a server
error, with a status code, content type and body the spec documents. Runs in-process on an empty memory; no model
or network is called (the GET operations never reach one)."""

import tempfile
from pathlib import Path

import schemathesis
from hypothesis import HealthCheck, settings
from schemathesis.checks import (
    content_type_conformance,
    not_a_server_error,
    response_schema_conformance,
    status_code_conformance,
)

from recall_api.config.settings import Settings
from recall_api.infra.app import create_app

KEY = "contract-test-key"
DATA = Path(tempfile.mkdtemp(prefix="recall-contract-"))
app = create_app(Settings(RECALL_DATA_DIR=DATA, RECALL_DEVICE_KEY=KEY, RECALL_TRACES="off"))
schema = schemathesis.openapi.from_asgi("/openapi.json", app).include(method="GET")
CHECKS = (not_a_server_error, status_code_conformance, content_type_conformance, response_schema_conformance)


@schema.parametrize()
@settings(max_examples=25, deadline=None, suppress_health_check=list(HealthCheck))
def test_get_operations_match_the_spec(case):
    case.call_and_validate(headers={"Authorization": f"Bearer {KEY}"}, checks=CHECKS)
