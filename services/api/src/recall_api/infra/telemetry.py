"""OpenTelemetry traces for every request and every outbound model call (httpx), so one upload or one question can
be followed end to end. Headers and bodies are not recorded, so keys never reach a trace."""

from __future__ import annotations

from typing import IO

from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter

from recall_api.config.settings import Settings

_provider: TracerProvider | None = None
_file: IO[str] | None = None


def setup(app: FastAPI, settings: Settings) -> None:
    global _provider, _file
    if settings.traces == "off":
        return
    if _provider is None:  # one provider per process; the app factory can run more than once
        _provider = TracerProvider(resource=Resource.create({"service.name": "recall-api"}))
        if settings.traces == "otlp":
            from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

            exporter = OTLPSpanExporter()  # endpoint from OTEL_EXPORTER_OTLP_ENDPOINT
        else:
            settings.log_dir.mkdir(parents=True, exist_ok=True)
            _file = (settings.log_dir / "traces.jsonl").open("a", encoding="utf-8")
            exporter = ConsoleSpanExporter(out=_file, formatter=lambda s: s.to_json(indent=None) + "\n")
        _provider.add_span_processor(BatchSpanProcessor(exporter))
        trace.set_tracer_provider(_provider)
        HTTPXClientInstrumentor().instrument()
    FastAPIInstrumentor.instrument_app(app, tracer_provider=_provider, excluded_urls="health")
