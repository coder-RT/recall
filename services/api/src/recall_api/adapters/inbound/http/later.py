"""Routes in the spec that are not built yet: they answer 501, never made-up data."""

from fastapi import APIRouter, Depends

from .deps import not_implemented, require_device_key

router = APIRouter(dependencies=[Depends(require_device_key)])


@router.get("/homes/{home_id}/room", tags=["homes"])
def get_room(home_id: str):
    raise not_implemented("The room model")


@router.get("/homes/{home_id}/objects", tags=["homes"])
def list_objects(home_id: str):
    raise not_implemented("The object list")


@router.post("/ask", tags=["ask"])
def ask():
    raise not_implemented("The Guide agent")


@router.post("/guidance/sessions", tags=["guidance"])
def start_guidance():
    raise not_implemented("Route planning")


@router.post("/guidance/sessions/{session_id}/verify", tags=["guidance"])
def verify(session_id: str):
    raise not_implemented("The arrival check")


@router.post("/transcribe", tags=["voice"])
def transcribe():
    raise not_implemented("Speech to text")
