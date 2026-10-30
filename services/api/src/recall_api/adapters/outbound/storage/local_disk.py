"""BlobStore on the Mac's disk (STORAGE=local, the default). Keys are relative paths under one root."""

from __future__ import annotations

import os
from collections.abc import Iterator
from pathlib import Path


class LocalDiskBlobStore:
    def __init__(self, root: str | Path) -> None:
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        p = (self.root / key).resolve()
        if self.root not in p.parents and p != self.root:
            raise ValueError(f"key escapes the store: {key}")
        return p

    def put(self, key: str, data: bytes) -> None:
        p = self._path(key)
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_suffix(p.suffix + ".tmp")
        tmp.write_bytes(data)
        os.replace(tmp, p)  # atomic: a half-written part is never seen as received

    def get(self, key: str) -> bytes:
        return self._path(key).read_bytes()

    def exists(self, key: str) -> bool:
        return self._path(key).is_file()

    def size(self, key: str) -> int:
        return self._path(key).stat().st_size

    def iter_chunks(self, key: str, chunk: int = 1 << 20) -> Iterator[bytes]:
        with self._path(key).open("rb") as f:
            while block := f.read(chunk):
                yield block

    def local_path(self, key: str) -> str | None:
        return str(self._path(key))
