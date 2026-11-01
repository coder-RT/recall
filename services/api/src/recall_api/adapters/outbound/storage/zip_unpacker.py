"""Unpacks an episode zip into the blob store; refuses paths that escape the episode folder."""

from __future__ import annotations

import hashlib
import io
import posixpath
import zipfile

from recall_api.application.ports import BlobStore, FileEntry

MAX_ENTRIES = 20_000  # a 3-minute room: a few hundred frames, each with depth and confidence
MAX_UNPACKED = 1024 * 1024 * 1024  # 1 GB unpacked from an episode of at most 200 MB


class ZipEpisodeUnpacker:
    def __init__(self, blobs: BlobStore) -> None:
        self.blobs = blobs

    def unpack(self, archive_key: str, dest_prefix: str) -> list[FileEntry]:
        out: list[FileEntry] = []
        with zipfile.ZipFile(io.BytesIO(self.blobs.get(archive_key))) as z:
            names = [n for n in z.namelist() if not n.endswith("/") and "__MACOSX" not in n]
            # a zip bomb is refused before anything is read: the sizes the archive itself declares
            if len(names) > MAX_ENTRIES or sum(z.getinfo(n).file_size for n in names) > MAX_UNPACKED:
                raise ValueError("archive too large when unpacked")
            # NSFileCoordinator zips the folder itself: strip one common top-level directory if there is one
            tops = {n.split("/", 1)[0] for n in names}
            strip = len(tops) == 1 and all("/" in n for n in names)
            for name in names:
                rel = name.split("/", 1)[1] if strip else name
                rel = posixpath.normpath(rel)
                if rel.startswith("..") or rel.startswith("/"):
                    raise ValueError(f"unsafe path in archive: {name}")
                with z.open(name) as f:  # never more than the declared size, whatever the header claims
                    data = f.read(z.getinfo(name).file_size + 1)
                if len(data) > z.getinfo(name).file_size:
                    raise ValueError(f"archive entry larger than declared: {name}")
                self.blobs.put(f"{dest_prefix}/{rel}", data)
                out.append(FileEntry(rel, len(data), hashlib.sha256(data).hexdigest()))
        return out
