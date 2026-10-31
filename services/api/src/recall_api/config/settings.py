"""Settings from the environment and .env (never logged). Every model is a Meta model (CLAUDE.md rule 8)."""

from __future__ import annotations

from pathlib import Path
from typing import Literal

from pydantic import AliasChoices, Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parents[5]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=REPO_ROOT / ".env", extra="ignore", populate_by_name=True)

    data_dir: Path = Field(REPO_ROOT / "data", alias="RECALL_DATA_DIR")
    database_url: str | None = Field(None, alias="RECALL_DATABASE_URL")
    storage: Literal["local", "r2"] = Field("local", alias="STORAGE")
    # shared with the phone and the pipeline; pairing, not a login
    device_key: SecretStr | None = Field(None, alias="RECALL_DEVICE_KEY")

    llm_provider: Literal["baseten_spark_open", "glimmer_hosted", "lmstudio", "meta"] = "baseten_spark_open"
    baseten_base_url: str | None = None
    baseten_api_key: SecretStr | None = None
    baseten_spark_open_model: str = "meta-models/muse-spark-open-1026"
    glimmer_base_url: str | None = None
    glimmer_api_key: SecretStr | None = None
    glimmer_model: str | None = None
    lmstudio_base_url: str = "http://localhost:1234/v1"
    lmstudio_model: str | None = None
    meta_muse_base_url: str | None = None
    meta_muse_api_key: SecretStr | None = None

    pipeline_command: str = "uv run --project services/pipeline recall-pipeline process"
    # queue: the Huey worker runs it (make worker); subprocess: start it right away (tests, no worker)
    pipeline_runner: Literal["queue", "subprocess"] = Field("queue", alias="RECALL_PIPELINE_RUNNER")
    # the warm pipeline (recall-pipeline serve); jobs fall back to a fresh process when it isn't running
    pipeline_server: str = Field("http://127.0.0.1:8766", alias="RECALL_PIPELINE_SERVER")

    # robots: the read-only export of one room's memory, off unless the owner turns it on; robots get their own key
    robot_export_enabled: bool = Field(False, alias="ROBOT_EXPORT_ENABLED")
    # one key for robots and other agents: the export and the Home Memory agent (A2A); never the phone's routes
    robot_key: SecretStr | None = Field(None, validation_alias=AliasChoices("RECALL_ROBOT_KEY", "A2A_HOME_MEMORY_KEY"))
    # the Home Memory agent over A2A (read-only "where is X?"), off unless the owner turns it on
    home_memory_a2a_enabled: bool = Field(False, alias="HOME_MEMORY_A2A_ENABLED")
    # how other agents reach this Mac (written into the Agent Card); a robot in Docker uses host.docker.internal
    public_url: str = Field("http://localhost:8000", alias="RECALL_PUBLIC_URL")
    home_id: str = Field("flat", alias="RECALL_HOME_ID")  # the home the Home Memory agent answers about

    # the home's clock, for "seen yesterday at 04:21" (sightings are stored in UTC)
    home_timezone: str = Field("Europe/Warsaw", alias="HOME_TIMEZONE")

    log_level: str = Field("INFO", alias="RECALL_LOG_LEVEL")
    # traces: "file" writes data/logs/traces.jsonl; "otlp" sends to OTEL_EXPORTER_OTLP_ENDPOINT; "off" for tests
    traces: Literal["file", "otlp", "off"] = Field("file", alias="RECALL_TRACES")

    @property
    def log_dir(self) -> Path:
        return self.data_dir / "logs"

    @property
    def db_url(self) -> str:
        return (
            self.database_url
            if self.database_url and self.database_url.startswith("sqlite")
            else (f"sqlite:///{self.data_dir / 'recall.db'}")
        )

    @classmethod
    def load(cls) -> Settings:
        return cls()
