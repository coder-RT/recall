"""Unpacks an episode zip into the blob store; refuses paths that escape the episode folder."""

from __future__ import annotations

import hashlib
import io
import posixpath
import zipfile

from recall_api.application.ports import BlobStore, FileEntry


class ZipEpisodeUnpacker:
    def __init__(self, blobs: BlobStore) -> None:
        self.blobs = blobs

    def unpack(self, archive_key: str, dest_prefix: str) -> list[FileEntry]:
        out: list[FileEntry] = []
        with zipfile.ZipFile(io.BytesIO(self.blobs.get(archive_key))) as z:
            names = [n for n in z.namelist() if not n.endswith("/") and "__MACOSX" not in n]
            # NSFileCoordinator zips the folder itself: strip one common top-level directory if there is one
            tops = {n.split("/", 1)[0] for n in names}
            strip = len(tops) == 1 and all("/" in n for n in names)
            for name in names:
                rel = name.split("/", 1)[1] if strip else name
                rel = posixpath.normpath(rel)
                if rel.startswith("..") or rel.startswith("/"):
                    raise ValueError(f"unsafe path in archive: {name}")
                data = z.read(name)
                self.blobs.put(f"{dest_prefix}/{rel}", data)
                out.append(FileEntry(rel, len(data), hashlib.sha256(data).hexdigest()))
        return out
