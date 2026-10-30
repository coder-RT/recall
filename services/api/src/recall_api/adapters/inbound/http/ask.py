"""Ask and speech to text: mapping only."""

from __future__ import annotations

import httpx
from fastapi import APIRouter, Depends, HTTPException, UploadFile

from .deps import container, require_device_key
from .models import Answer, AskRequest, Transcript

router = APIRouter(dependencies=[Depends(require_device_key)])


def _unavailable(e: Exception) -> HTTPException:
    return HTTPException(
        503, {"error": "model_unavailable", "detail": f"The model could not be reached: {type(e).__name__}."}
    )


@router.post("/ask", response_model=Answer, tags=["ask"])
def ask(body: AskRequest, c=Depends(container)) -> Answer:
    try:
        a = c.ask(body.home_id, body.question, body.session_id)
    except (httpx.HTTPError, RuntimeError) as e:
        raise _unavailable(e) from e
    return Answer(
        text=a.text,
        grounded=a.grounded,
        object_id=a.object_id,
        tool_calls=a.tool_calls,
        model=a.model,
        latency_ms=a.latency_ms,
    )


@router.post("/transcribe", response_model=Transcript, tags=["voice"])
async def transcribe(audio: UploadFile, c=Depends(container)) -> Transcript:
    import time

    data = await audio.read()
    t0 = time.perf_counter()
    try:
        text = c.transcriber.transcribe(data, audio.content_type or "")
    except ValueError as e:
        raise HTTPException(422, {"error": "wrong_format", "detail": str(e)}) from e
    except (httpx.HTTPError, RuntimeError) as e:
        raise _unavailable(e) from e
    return Transcript(text=text, model="muse-voice-transcribe-1.0", latency_ms=int((time.perf_counter() - t0) * 1000))
