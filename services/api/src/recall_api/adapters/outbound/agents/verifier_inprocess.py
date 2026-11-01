"""ArrivalVerifier in the API's own process: the Verifier's use case called directly (the default, and the live demo's
transport). Its memory updates stay inside the API, so the one-writer rule holds."""

from __future__ import annotations

from recall_api.application.verify_arrival import Verification, VerifyArrival
from recall_api.domain.spatial import CameraView


class InProcessVerifier:
    def __init__(self, verify: VerifyArrival) -> None:
        self.verify = verify

    def __call__(self, session_id: str, jpeg: bytes, view: CameraView) -> Verification:
        return self.verify(session_id, jpeg, view)
