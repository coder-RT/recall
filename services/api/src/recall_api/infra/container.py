"""Composition root: the only place that builds adapters and hands them to use cases."""

from __future__ import annotations

import json
from dataclasses import dataclass
from functools import cached_property

from recall_api.adapters.outbound.llm.openai_compatible import from_settings as llm_from_settings
from recall_api.adapters.outbound.persistence.sqlite import SqliteHomes, SqliteObjects, SqliteScans
from recall_api.adapters.outbound.storage.local_disk import LocalDiskBlobStore
from recall_api.adapters.outbound.storage.zip_unpacker import ZipEpisodeUnpacker
from recall_api.adapters.outbound.voice.muse_transcribe import MuseTranscriber
from recall_api.application.ask_where_is import AskWhereIs
from recall_api.application.ingest_scan import IngestScan
from recall_api.application.tools import Tools
from recall_api.application.upload_scan import UploadScan
from recall_api.config.settings import REPO_ROOT, Settings
from recall_api.infra.clock import SystemClock
from recall_api.infra.db import API_ROOT, make_engine, migrate
from recall_api.infra.pipeline_trigger import SubprocessPipelineTrigger
from recall_api.util.ids import new_id


@dataclass
class Container:
    settings: Settings

    @cached_property
    def engine(self):
        engine = make_engine(self.settings.db_url)
        migrate(self.settings.db_url)
        return engine

    @cached_property
    def blobs(self):
        if self.settings.storage != "local":
            raise RuntimeError("STORAGE=r2 is not implemented yet; use STORAGE=local (the default)")
        return LocalDiskBlobStore(self.settings.data_dir / "blobs")

    @cached_property
    def homes(self):
        return SqliteHomes(self.engine)

    @cached_property
    def scans(self):
        return SqliteScans(self.engine)

    @cached_property
    def objects(self):
        return SqliteObjects(self.engine)

    @cached_property
    def clock(self):
        return SystemClock()

    @cached_property
    def upload_scan(self) -> UploadScan:
        trigger = SubprocessPipelineTrigger(self.settings.pipeline_command, REPO_ROOT, self.settings.data_dir / "logs")
        return UploadScan(self.scans, self.homes, self.blobs, ZipEpisodeUnpacker(self.blobs), trigger, self.clock)

    @cached_property
    def ingest_scan(self) -> IngestScan:
        return IngestScan(self.scans, self.homes, self.objects, self.clock, new_id)

    @cached_property
    def tools(self) -> Tools:
        return Tools(self.homes, self.objects, self.clock)

    @cached_property
    def ask(self) -> AskWhereIs:
        schemas = json.loads((API_ROOT / "resources" / "tools.json").read_text())
        return AskWhereIs(llm_from_settings(self.settings), self.tools, schemas, self.homes)

    @cached_property
    def transcriber(self) -> MuseTranscriber:
        key = self.settings.meta_muse_api_key
        if key is None:
            raise RuntimeError("META_MUSE_API_KEY is not set")
        return MuseTranscriber(key.get_secret_value())
