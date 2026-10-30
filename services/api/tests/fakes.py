"""Test doubles. Allowed only inside tests/ (unit tests never touch the network or the disk)."""

from __future__ import annotations

import hashlib
import io
import zipfile
from collections.abc import Iterator
from datetime import UTC, datetime

from recall_api.application.ports import FileEntry


class MemoryBlobs:
    def __init__(self) -> None:
        self.data: dict[str, bytes] = {}

    def put(self, key, data):
        self.data[key] = data

    def get(self, key):
        return self.data[key]

    def exists(self, key):
        return key in self.data

    def size(self, key):
        return len(self.data[key])

    def iter_chunks(self, key, chunk=1 << 20) -> Iterator[bytes]:
        yield self.data[key]

    def local_path(self, key):
        return None


class MemoryUnpacker:
    def __init__(self, blobs: MemoryBlobs) -> None:
        self.blobs = blobs

    def unpack(self, archive_key, dest_prefix):
        out = []
        with zipfile.ZipFile(io.BytesIO(self.blobs.get(archive_key))) as z:
            for n in z.namelist():
                d = z.read(n)
                out.append(FileEntry(n, len(d), hashlib.sha256(d).hexdigest()))
        return out


class RecordingTrigger:
    def __init__(self) -> None:
        self.started: list[tuple[str, str]] = []

    def start(self, scan_id, episode_dir):
        self.started.append((scan_id, episode_dir))


class FixedClock:
    def now(self):
        return datetime(2026, 10, 30, 12, 0, tzinfo=UTC)


class MemoryRepo:
    def __init__(self) -> None:
        self.items: dict = {}

    def get(self, key):
        return self.items.get(key)

    def save(self, item):
        self.items[item.id] = item

    def delete(self, key):
        self.items.pop(key, None)

    def list_for_home(self, home_id):
        return [i for i in self.items.values() if i.home_id == home_id]


def episode_zip(files: dict[str, bytes]) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, data in files.items():
            z.writestr(name, data)
    return buf.getvalue()
