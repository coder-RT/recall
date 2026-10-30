"""Request plumbing shared by the routers: the container and the device-key check."""

from __future__ import annotations

import hmac

from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

_bearer = HTTPBearer(auto_error=False)


def container(request: Request):
    return request.app.state.container


def require_device_key(request: Request, creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> None:
    expected = request.app.state.container.settings.device_key
    if expected is None:
        raise HTTPException(503, {"error": "device_key_unset", "detail": "Set RECALL_DEVICE_KEY in .env on the Mac."})
    if creds is None or not hmac.compare_digest(creds.credentials, expected.get_secret_value()):
        raise HTTPException(401, {"error": "unauthorized", "detail": "Missing or wrong device key."})


def not_implemented(feature: str) -> HTTPException:
    return HTTPException(501, {"error": "not_implemented", "detail": f"{feature} is not built yet."})
