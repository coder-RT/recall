"""Composition root: the only place that builds adapters and hands them to use cases."""

from __future__ import annotations

import json
from dataclasses import dataclass
from functools import cached_property
from zoneinfo import ZoneInfo

from recall_api.adapters.outbound.llm.openai_compatible import from_settings as llm_from_settings
from recall_api.adapters.outbound.persistence.sqlite import SqliteHomes, SqliteObjects, SqliteScans
from recall_api.adapters.outbound.safety.fallback import FirstAvailable
from recall_api.adapters.outbound.safety.prompt_guard_pipeline import PromptGuardViaPipeline
from recall_api.adapters.outbound.safety.spark_screen_meta_api import SparkScreener
from recall_api.adapters.outbound.storage.local_disk import LocalDiskBlobStore
from recall_api.adapters.outbound.storage.zip_unpacker import ZipEpisodeUnpacker
from recall_api.adapters.outbound.vision.sam31_meta_api import Sam31MetaApi
from recall_api.adapters.outbound.vision.spark_vision_meta_api import SparkVisionMetaApi
from recall_api.adapters.outbound.voice.muse_transcribe import MuseTranscriber
from recall_api.application.answer_external_query import AnswerExternalQuery
from recall_api.application.ask_where_is import AskWhereIs
from recall_api.application.correct_object import CorrectObject
from recall_api.application.export_for_robot import ExportForRobot
from recall_api.application.ingest_scan import IngestScan
from recall_api.application.plan_guidance import PlanGuidance
from recall_api.application.tools import Tools
from recall_api.application.upload_scan import UploadScan
from recall_api.application.verify_arrival import VerifyArrival
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
        if self.settings.pipeline_runner == "queue":
            from recall_api.infra.jobs import QueuedPipelineTrigger

            trigger = QueuedPipelineTrigger()
        else:
            trigger = SubprocessPipelineTrigger(self.settings.pipeline_command, REPO_ROOT, self.settings.log_dir)
        return UploadScan(self.scans, self.homes, self.blobs, ZipEpisodeUnpacker(self.blobs), trigger, self.clock)

    @cached_property
    def ingest_scan(self) -> IngestScan:
        return IngestScan(self.scans, self.homes, self.objects, self.clock, new_id)

    @cached_property
    def correct_object(self) -> CorrectObject:
        return CorrectObject(self.objects)

    @cached_property
    def guidance(self) -> PlanGuidance:
        return PlanGuidance(self.homes, self.scans, self.objects, self.blobs, new_id)

    @cached_property
    def screener(self) -> FirstAvailable:
        """Llama Prompt Guard when its weights are there, else Muse Spark as the judge; neither: refuse."""
        key = self.settings.device_key.get_secret_value() if self.settings.device_key else None
        screens = [PromptGuardViaPipeline(self.settings.pipeline_server, key)]
        if self.settings.meta_muse_api_key is not None:
            screens.append(SparkScreener(self.settings.meta_muse_api_key.get_secret_value()))
        return FirstAvailable(*screens)

    @cached_property
    def answer_external_query(self) -> AnswerExternalQuery:
        return AnswerExternalQuery(self.screener, self.tools, self.objects, self.scans)

    @cached_property
    def export_for_robot(self) -> ExportForRobot:
        return ExportForRobot(self.homes, self.scans, self.objects, self.blobs, self.clock)

    @cached_property
    def tools(self) -> Tools:
        return Tools(self.homes, self.objects, self.clock, self.guidance, ZoneInfo(self.settings.home_timezone))

    @cached_property
    def ask(self) -> AskWhereIs:
        schemas = json.loads((API_ROOT / "resources" / "tools.json").read_text())
        return AskWhereIs(llm_from_settings(self.settings), self.tools, schemas, self.homes)

    @cached_property
    def verify_arrival(self) -> VerifyArrival:
        key = self.settings.meta_muse_api_key
        if key is None:
            raise RuntimeError("META_MUSE_API_KEY is not set: the arrival check uses SAM 3.1 on the Meta Model API")
        k = key.get_secret_value()
        return VerifyArrival(self.guidance, self.objects, Sam31MetaApi(k), SparkVisionMetaApi(k), self.clock, new_id)

    @cached_property
    def transcriber(self) -> MuseTranscriber:
        key = self.settings.meta_muse_api_key
        if key is None:
            raise RuntimeError("META_MUSE_API_KEY is not set")
        return MuseTranscriber(key.get_secret_value())
