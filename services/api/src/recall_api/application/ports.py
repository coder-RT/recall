"""What the use cases need from the outside world. Adapters implement these; infra/container.py wires them."""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Protocol


class Clock(Protocol):
    def now(self) -> datetime: ...


class BlobStore(Protocol):
    """Episode storage: the Mac's disk by default (STORAGE=local), R2 optionally."""

    def put(self, key: str, data: bytes) -> None: ...
    def get(self, key: str) -> bytes: ...
    def exists(self, key: str) -> bool: ...
    def size(self, key: str) -> int: ...
    def iter_chunks(self, key: str, chunk: int = 1 << 20) -> Iterator[bytes]: ...
    def local_path(self, key: str) -> str | None:
        """A filesystem path for tools that need one (the pipeline), or None for remote stores."""
        ...


@dataclass(frozen=True)
class FileEntry:
    path: str
    size: int
    sha256: str


class EpisodeUnpacker(Protocol):
    """Unpacks an uploaded episode archive into the blob store and lists what it contained (paths are checked)."""

    def unpack(self, archive_key: str, dest_prefix: str) -> list[FileEntry]: ...


class PipelineTrigger(Protocol):
    def start(self, name: str, scan_id: str, episode_dir: str) -> None: ...  # name: the scan's folder name
    def warm(self) -> None: ...  # a scan started uploading: get the model loaded meanwhile (best effort)


@dataclass
class ToolCall:
    id: str
    name: str
    arguments: dict[str, Any]


@dataclass
class ChatReply:
    text: str | None
    tool_calls: list[ToolCall] = field(default_factory=list)
    model: str = ""


class LlmProvider(Protocol):
    """An OpenAI-compatible chat model with tool calling (Muse Spark Open, Glimmer, hosted Spark)."""

    model: str

    def chat(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]]) -> ChatReply: ...


class VisionProvider(Protocol):
    """Muse Spark 1.1, asked only as the Verifier's tie-break: 'yes', 'no' or 'unsure'."""

    def is_visible(self, label: str, jpeg: bytes) -> str: ...


@dataclass
class Mask:
    label: str
    score: float
    # row-major boolean mask at the image's size, or a bounding box when the API returns only boxes
    mask: Any | None
    box: tuple[float, float, float, float] | None


class Segmenter(Protocol):
    """SAM 3.1 over HTTP (Meta Model API). Finds things by text prompt."""

    def segment(self, jpeg: bytes, prompts: list[str]) -> list[Mask]: ...


class Transcriber(Protocol):
    """Muse Voice Transcribe: the only speech model."""

    def transcribe(self, audio: bytes, content_type: str) -> str: ...


@dataclass(frozen=True)
class Screening:
    """A screener's verdict. `safe` only when the screen ran and found no attack: unavailable means not safe."""

    safe: bool
    reason: str  # "ok", "attack", or "unavailable"


class PromptScreener(Protocol):
    """Llama Prompt Guard: screens every message from outside before any tool runs."""

    def screen(self, text: str) -> Screening: ...
