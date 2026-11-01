"""FastAPI factory. Swagger UI at /docs serves the bundled spec from resources/."""

from __future__ import annotations

import hmac
import json
import logging
import time
import uuid

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from recall_api.adapters.inbound.http import (
    answers,
    ask,
    audit,
    guidance,
    health,
    homes,
    privacy,
    robots,
    scans,
    sharing,
)
from recall_api.config.settings import Settings
from recall_api.domain.audit import Action, Actor, Outcome
from recall_api.infra import logging as recall_logging
from recall_api.infra import telemetry
from recall_api.infra.container import Container
from recall_api.infra.db import API_ROOT
from recall_api.util.request_context import request_id

log = logging.getLogger("recall_api.http")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.load()
    recall_logging.configure(settings.log_dir, settings.log_level)
    app = FastAPI(title="Recall API", version="0.1.0")
    app.state.container = Container(settings)
    for r in (
        health.router,
        scans.router,
        homes.router,
        ask.router,
        guidance.router,
        robots.router,
        sharing.router,
        audit.router,
        privacy.router,
        answers.router,
    ):
        app.include_router(r)
    _mount_home_memory(app, settings)

    @app.middleware("http")
    async def _access_log(request: Request, call_next):  # noqa: ANN001, ANN202
        # one line per request: what, from where, how big, how long, the answer; never headers or bodies
        rid = request.headers.get("x-request-id") or uuid.uuid4().hex[:12]
        request_id.set(rid)  # audit events recorded during this request name it
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

    @app.exception_handler(RequestValidationError)
    async def _invalid(request: Request, exc: RequestValidationError) -> JSONResponse:
        # the spec's Error shape, like every other refusal: one code, one plain sentence (FastAPI's own is a list)
        parts = [".".join(str(x) for x in e.get("loc", ())) + ": " + str(e.get("msg", "")) for e in exc.errors()[:3]]
        body = {"error": "invalid", "detail": "; ".join(parts) or "Invalid request."}
        log.warning("refused", extra={"fields": {"path": request.url.path, "status": 422, **body}})
        return JSONResponse(body, status_code=422)

    bundled = API_ROOT / "build" / "openapi.json"
    if bundled.exists():  # the real spec (make bundle-spec), not FastAPI's generated one
        spec = json.loads(bundled.read_text())
        app.openapi = lambda: spec  # type: ignore[method-assign]
    telemetry.setup(app, settings)
    return app


def _mount_home_memory(app: FastAPI, settings: Settings) -> None:
    """The Home Memory agent (A2A). Mounted always; the gate below answers 404 while the owner hasn't turned it on,
    and every call but the Agent Card needs the robot key."""
    from recall_api.adapters.inbound.a2a import home_memory_server as hm

    c = app.state.container
    card = hm.load_card(API_ROOT / "resources" / "agents" / "home-memory.card.json", settings.public_url)
    app.router.routes.extend(hm.routes(lambda h, t: c.answer_external_query(h, t), settings.home_id, card))

    @app.middleware("http")
    async def _home_memory_gate(request: Request, call_next):  # noqa: ANN202
        if not request.url.path.startswith(hm.PATH):
            return await call_next(request)
        if not c.robot_access.a2a_open:
            c.auditor(Action.HOME_MEMORY_QUERY, Actor.UNKNOWN, Outcome.REFUSED, path=request.url.path, why="access off")
            return JSONResponse({"error": "not_found", "detail": "Home Memory sharing is off."}, status_code=404)
        if request.url.path != hm.CARD_PATH:
            keys = [k.get_secret_value() for k in (settings.robot_key, settings.device_key) if k is not None]
            got = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
            if not keys or not any(hmac.compare_digest(got, k) for k in keys):
                c.auditor(Action.AUTH_REFUSED, Actor.UNKNOWN, Outcome.REFUSED, path=request.url.path,
                          method=request.method, why="no key" if not got else "wrong key")  # fmt: skip
                return JSONResponse({"error": "unauthorized", "detail": "Missing or wrong key."}, status_code=401)
        return await call_next(request)


def main() -> None:
    uvicorn.run("recall_api.infra.app:create_app", factory=True, host="0.0.0.0", port=8000)
