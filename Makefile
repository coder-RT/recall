# Recall: one entry point for every service. Run `make help`.
SHELL := /bin/bash
API := services/api
PIPE := services/pipeline
# where the API listens: the LAN by default so the phone reaches it; BIND=127.0.0.1 when a Cloudflare Tunnel is the only way in
BIND ?= 0.0.0.0
WEB := apps/web
REDOCLY := npx -y @redocly/cli@2.72.1

.PHONY: help setup dev worker robot-export regression viewer public-scan live demo record probes diagrams pair rerun test test-all lint lint-imports migrate bundle-spec gen-models gen-swift-client eval

help:
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-18s %s\n", $$1, $$2}'

setup: ## Install Python 3.12 services (uv), the web app (pnpm) and generate the spec bundle and models
	cd $(API) && uv sync
	cd $(PIPE) && uv sync
	pnpm install
	$(MAKE) bundle-spec gen-models migrate

dev: ## Run the API on :8000 (reachable on the LAN), the scan worker and the web app on :3000
	( cd $(API) && RECALL_BIND_HOST=$(BIND) uv run recall-api ) & $(MAKE) worker & ( cd $(WEB) && pnpm dev ) ; wait

worker: ## The scan job worker (Huey on SQLite) and the warm pipeline (MapAnything kept loaded, freed after 10 min idle)
	( cd $(PIPE) && uv run recall-pipeline serve ) & ( cd $(API) && uv run huey_consumer recall_api.infra.jobs.huey -w 1 -k thread ) ; wait

# HOME is also the shell's home folder: only a HOME=<id> given to make picks the home
ROBOT_HOME = $(or $(HOME_ID),$(if $(filter command line,$(origin HOME)),$(HOME),flat))

robot-export: ## One room's memory for a robot (Nav2 map, things, furniture): make robot-export [HOME=flat] [ROOM=...] -> exports/robot/<home>/
	cd $(API) && uv run python -m recall_api.infra.robot_export --home "$(ROBOT_HOME)" $(if $(ROOM),--room "$(ROOM)",) --out "$(CURDIR)/exports/robot/$(ROBOT_HOME)"

regression: ## Re-run every processed scan now (no posting; cached SAM answers) and compare with the last run
	cd $(API) && uv run python -c "from recall_api.infra import jobs, regression; print('\n'.join(regression.run(jobs.settings, jobs.run_pipeline)))"

public-scan: ## The real scan for the public site, geometry only (no photo data): make public-scan [HOME_ID=flat] -> apps/web/public/real-scan/<home>/ (review before committing)
	@H="$(or $(HOME_ID),flat)"; \
	case "$$H" in *[!a-z0-9-]*|"") echo "HOME_ID: lower-case letters, digits and hyphens only."; exit 2;; esac; \
	ID=$$(sqlite3 data/recall.db "SELECT id FROM scans WHERE home_id = '$$H' AND status = 'processed' ORDER BY created_at DESC LIMIT 1" 2>/dev/null); \
	E=$$(ls -d data/blobs/scans/*_$$ID/episode 2>/dev/null | head -1); \
	if [ -z "$$ID" ] || [ ! -f "$$E/home_colors.npy" ]; then echo "No processed scan of '$$H' yet."; exit 1; fi; \
	cd $(PIPE)/scripts && uv run --project .. python export_viewer_scan.py --public "$(CURDIR)/$$E" "$(CURDIR)/$(WEB)/public/real-scan/$$H" && \
	echo "Review apps/web/public/real-scan/$$H/ (no photos, nothing personal) before committing it."

viewer: ## Export a home's newest processed scan for /homes/<home>/viewer: make viewer [HOME_ID=flat] (gitignored output)
	@H="$(or $(HOME_ID),flat)"; \
	case "$$H" in *[!a-z0-9-]*|"") echo "HOME_ID: lower-case letters, digits and hyphens only."; exit 2;; esac; \
	ID=$$(sqlite3 data/recall.db "SELECT id FROM scans WHERE home_id = '$$H' AND status = 'processed' ORDER BY created_at DESC LIMIT 1" 2>/dev/null); \
	E=$$(ls -d data/blobs/scans/*_$$ID/episode 2>/dev/null | head -1); \
	if [ -z "$$ID" ] || [ ! -f "$$E/home_colors.npy" ]; then \
		echo "No processed scan of '$$H' yet: run make live, scan a room with the iPhone app (home: $$H) and upload it."; exit 1; fi; \
	cd $(PIPE)/scripts && uv run --project .. python export_viewer_scan.py "$(CURDIR)/$$E" "$(CURDIR)/$(WEB)/public/local-scan/$$H" && \
	echo "Open http://localhost:3000/homes/$$H/viewer"

live: ## The API with real Meta model calls (keys from .env), and the scan worker
	( cd $(API) && RECALL_BIND_HOST=$(BIND) uv run recall-api ) & $(MAKE) worker ; wait

demo: ## No keys: the API on a memory built from a recorded real scan; the Guide's replies are replayed (labelled recorded)
	cd $(API) && uv run python -m recall_api.infra.demo serve $(if $(PORT),--port $(PORT))

record: ## Re-record samples/replay/ with real Muse Spark Open calls: make record RESULT=<result.json> ROOM="Living room" AT=<iso>
	cd $(API) && uv run python -m recall_api.infra.demo record "$(abspath $(RESULT))" --room "$(ROOM)" --captured-at "$(AT)"

diagrams: ## Redraw docs/diagrams/*.svg from the Mermaid sources (mermaid-cli; set PUPPETEER_EXECUTABLE_PATH to use a local Chrome)
	@for f in docs/diagrams/*.mmd; do \
		npx -y @mermaid-js/mermaid-cli@11.4.2 -i $$f -o $${f%.mmd}.svg -c docs/diagrams/mermaid.config.json -b white -q || exit 1; \
	done; echo "Redrew $$(ls docs/diagrams/*.mmd | wc -l | tr -d ' ') diagrams"

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

test-all: ## Every suite (API, pipeline, lint, imports, web, iOS unit + UI), logs kept in data/test-runs/ (gitignored): make test-all [SUITES="api pipeline"]
	python3 scripts/test_all.py

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
