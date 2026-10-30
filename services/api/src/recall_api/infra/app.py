"""FastAPI factory. Swagger UI at /docs serves the bundled spec from resources/."""

from __future__ import annotations

import json

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

from recall_api.adapters.inbound.http import ask, health, homes, later, scans
from recall_api.config.settings import Settings
from recall_api.infra.container import Container
from recall_api.infra.db import API_ROOT


def create_app(settings: Settings | None = None) -> FastAPI:
    app = FastAPI(title="Recall API", version="0.1.0")
    app.state.container = Container(settings or Settings.load())
    for r in (health.router, scans.router, homes.router, ask.router, later.router):
        app.include_router(r)

    @app.exception_handler(HTTPException)
    async def _errors(_: Request, exc: HTTPException) -> JSONResponse:
        body = exc.detail if isinstance(exc.detail, dict) else {"error": "error", "detail": str(exc.detail)}
        return JSONResponse(body, status_code=exc.status_code)

    bundled = API_ROOT / "build" / "openapi.json"
    if bundled.exists():  # the real spec (make bundle-spec), not FastAPI's generated one
        spec = json.loads(bundled.read_text())
        app.openapi = lambda: spec  # type: ignore[method-assign]
    return app


def main() -> None:
    uvicorn.run("recall_api.infra.app:create_app", factory=True, host="0.0.0.0", port=8000)
