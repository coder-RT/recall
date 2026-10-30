# Recall: one entry point for every service. Run `make help`.
SHELL := /bin/bash
API := services/api
PIPE := services/pipeline
WEB := apps/web
REDOCLY := npx -y @redocly/cli@2.72.1

.PHONY: help setup dev live demo probes pair rerun test lint lint-imports migrate bundle-spec gen-models gen-swift-client eval

help:
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-18s %s\n", $$1, $$2}'

setup: ## Install Python 3.12 services (uv), the web app (pnpm) and generate the spec bundle and models
	cd $(API) && uv sync
	cd $(PIPE) && uv sync
	pnpm install
	$(MAKE) bundle-spec gen-models migrate

dev: ## Run the API on :8000 (reachable on the LAN) and the web app on :3000
	( cd $(API) && uv run recall-api ) & ( cd $(WEB) && pnpm dev ) ; wait

live: ## The API with real Meta model calls (keys from .env)
	cd $(API) && uv run recall-api

demo: ## Replay recordings of real runs (samples/replay/); none exist until a real run is recorded
	@if [ -d samples/replay ] && [ -n "$$(ls -A samples/replay 2>/dev/null)" ]; then \
		echo "replay is not built yet"; exit 1; \
	else echo "No recordings of real runs yet: run 'make live' first."; exit 1; fi

probes: ## One real call per Meta model or service; appends results to docs/verification.md (never in CI)
	cd $(API) && uv run python ../../scripts/probes/run.py

pair: ## Pairing QR code for the iPhone: make pair URL=https://<mac>.ts.net:8445 [HOME_ID=flat]
	swift scripts/pair.swift "$(URL)" "$(or $(HOME_ID),flat)"

rerun: ## Replay a stored episode into the Rerun viewer: make rerun EPISODE=<path>
	@test -n "$(EPISODE)" || (echo "usage: make rerun EPISODE=<path to an episode folder>"; exit 2)
	cd $(PIPE) && RERUN=1 uv run recall-pipeline process "$(abspath $(EPISODE))" --scan-id rerun --no-post

test: ## Unit, integration and contract tests for both services
	cd $(API) && uv run pytest
	cd $(PIPE) && uv run pytest

lint: ## ruff for both services, ESLint for the web app
	cd $(API) && uv run ruff check . && uv run ruff format --check .
	cd $(PIPE) && uv run ruff check . && uv run ruff format --check .
	cd $(WEB) && pnpm lint

lint-imports: ## The hexagonal dependency rule (import-linter) for both services
	cd $(API) && uv run lint-imports
	cd $(PIPE) && uv run lint-imports

migrate: ## Apply the SQLite migrations
	cd $(API) && uv run alembic upgrade head

bundle-spec: ## Bundle resources/openapi.yaml into one file
	cd $(API) && $(REDOCLY) lint resources/openapi.yaml && mkdir -p build && $(REDOCLY) bundle resources/openapi.yaml -o build/openapi.json

gen-models: bundle-spec ## Pydantic models from the spec into adapters/inbound/http/models.py
	cd $(API) && uv run datamodel-codegen --input build/openapi.json --input-file-type openapi \
		--output src/recall_api/adapters/inbound/http/models.py --output-model-type pydantic_v2.BaseModel \
		--target-python-version 3.12 --use-annotated --field-constraints --use-standard-collections \
		--use-union-operator --disable-timestamp --formatters ruff-format

gen-swift-client: bundle-spec ## Swift client from the spec (swift-openapi-generator, built from apps/ios)
	cd apps/ios && ./scripts/gen-client.sh ../../$(API)/build/openapi.json

eval: ## The 30-question evaluation (needs a processed real scan)
	@echo "evals/ is built in phase 2"; exit 1
