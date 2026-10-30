"""FastAPI factory. Swagger UI at /docs serves the bundled spec from resources/."""

from __future__ import annotations

import json
import logging
import time
import uuid

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

from recall_api.adapters.inbound.http import ask, guidance, health, homes, scans
from recall_api.config.settings import Settings
from recall_api.infra import logging as recall_logging
from recall_api.infra import telemetry
from recall_api.infra.container import Container
from recall_api.infra.db import API_ROOT

log = logging.getLogger("recall_api.http")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.load()
    recall_logging.configure(settings.log_dir, settings.log_level)
    app = FastAPI(title="Recall API", version="0.1.0")
    app.state.container = Container(settings)
    for r in (health.router, scans.router, homes.router, ask.router, guidance.router):
        app.include_router(r)

    @app.middleware("http")
    async def _access_log(request: Request, call_next):  # noqa: ANN001, ANN202
        # one line per request: what, from where, how big, how long, the answer; never headers or bodies
        rid = request.headers.get("x-request-id") or uuid.uuid4().hex[:12]
        t0 = time.perf_counter()
        fields = {
            "request_id": rid,
            "method": request.method,
            "path": request.url.path,
            "client": request.client.host if request.client else None,
            "bytes_in": request.headers.get("content-length"),
            "user_agent": request.headers.get("user-agent"),
        }
        try:
            response = await call_next(request)
        except Exception:
            fields["ms"] = round((time.perf_counter() - t0) * 1000)
            log.exception("request failed", extra={"fields": fields})
            return JSONResponse({"error": "internal", "detail": f"Server error, request {rid}."}, status_code=500)
        fields.update(status=response.status_code, ms=round((time.perf_counter() - t0) * 1000))
        log.log(logging.WARNING if response.status_code >= 400 else logging.INFO, "request", extra={"fields": fields})
        response.headers["x-request-id"] = rid
        return response

    @app.exception_handler(HTTPException)
    async def _errors(request: Request, exc: HTTPException) -> JSONResponse:
        body = exc.detail if isinstance(exc.detail, dict) else {"error": "error", "detail": str(exc.detail)}
        log.warning("refused", extra={"fields": {"path": request.url.path, "status": exc.status_code, **body}})
        return JSONResponse(body, status_code=exc.status_code)

    bundled = API_ROOT / "build" / "openapi.json"
    if bundled.exists():  # the real spec (make bundle-spec), not FastAPI's generated one
        spec = json.loads(bundled.read_text())
        app.openapi = lambda: spec  # type: ignore[method-assign]
    telemetry.setup(app, settings)
    return app


def main() -> None:
    uvicorn.run("recall_api.infra.app:create_app", factory=True, host="0.0.0.0", port=8000)
