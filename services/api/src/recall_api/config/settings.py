"""Settings from the environment and .env (never logged). Every model is a Meta model (CLAUDE.md rule 8)."""

from __future__ import annotations

from pathlib import Path
from typing import Literal

from pydantic import Field, SecretStr
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
