"""Request plumbing shared by the routers: the container and the device-key check."""

from __future__ import annotations

import hmac

from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from recall_api.domain.audit import Action, Actor, Outcome

_bearer = HTTPBearer(auto_error=False)


def container(request: Request):
    return request.app.state.container


def refused(request: Request, why: str) -> None:
    """A call without a valid key, in the audit log (the path and why; never what was sent as a key)."""
    c = request.app.state.container
    c.auditor(
        Action.AUTH_REFUSED, Actor.UNKNOWN, Outcome.REFUSED, path=request.url.path, method=request.method, why=why
    )


def caller(request: Request) -> Actor:
    """Who called, by the key they used: the owner's device key or the robot key."""
    s = request.app.state.container.settings
    got = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    if s.device_key is not None and hmac.compare_digest(got, s.device_key.get_secret_value()):
        return Actor.OWNER
    if s.robot_key is not None and hmac.compare_digest(got, s.robot_key.get_secret_value()):
        return Actor.ROBOT
    return Actor.UNKNOWN


def require_device_key(request: Request, creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> None:
    expected = request.app.state.container.settings.device_key
    if expected is None:
        raise HTTPException(503, {"error": "device_key_unset", "detail": "Set RECALL_DEVICE_KEY in .env on the Mac."})
    if creds is None or not hmac.compare_digest(creds.credentials, expected.get_secret_value()):
        refused(request, "no key" if creds is None else "wrong key")
        raise HTTPException(401, {"error": "unauthorized", "detail": "Missing or wrong device key."})


def require_robot_or_device_key(
    request: Request, creds: HTTPAuthorizationCredentials | None = Depends(_bearer)
) -> None:
    """The robot's own read-only key, or the owner's device key."""
    settings = request.app.state.container.settings
    keys = [k.get_secret_value() for k in (settings.robot_key, settings.device_key) if k is not None]
    if not keys:
        raise HTTPException(503, {"error": "key_unset", "detail": "Set RECALL_ROBOT_KEY in .env on the Mac."})
    if creds is None or not any(hmac.compare_digest(creds.credentials, k) for k in keys):
        refused(request, "no key" if creds is None else "wrong key")
        raise HTTPException(401, {"error": "unauthorized", "detail": "Missing or wrong key."})


def not_implemented(feature: str) -> HTTPException:
    return HTTPException(501, {"error": "not_implemented", "detail": f"{feature} is not built yet."})
