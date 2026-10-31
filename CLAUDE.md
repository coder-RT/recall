# CLAUDE.md: Recall

Standing context for Claude Code. Read this fully before any task. When this file and a request disagree, ask.
Section 10 lists facts that are **not yet verified**: never build on one of them until it is checked.

## 1. What Recall is

Voice-first 3D memory of your home for blind and low-vision people. Walk through once with an iPhone,
then ask "where are my keys?" and hear step-by-step directions.

- Event: Meta Global AI Developer Hackathon, **Indie track**, theme **Build for Your World**.
- Hacking window: **Oct 26 to Nov 4, 2026**. Deadline: **Wed Nov 4, 9:00 PM EST = 03:00 Thu Nov 5 Warsaw** (participant guide). **Aim to submit Nov 4 evening.**
- Judging: stage 1 pass/fail (fits theme, uses Meta AI products) → stage 2 rubric 0 to 10 (**Impact 30%, Use of Meta AI Tooling 25%, Demo 25%, Technical Depth & Execution 20%**) → stage 3 on Nov 9: final judges watch the top 5 videos live and rank them on the same rubric.
- Kickoff wording for Indie: creativity, technical ambition, **whether it works**. Not marking clearly what was built during the event can disqualify (judges' discretion).
- Bonus prizes targeted: Best Build on Meta Open Weights (the Guide runs on **Muse Spark Open or Muse Glimmer** in the demo; the bonus names only these two), Best Agentic Use-Case, Most Viral, Community Vote.
- Demo video: **one video, 3 minutes, working product only** (no slides), English. It opens with
  "Built during the hackathon, Oct 26 to Nov 4. Pre-existing work: none."
- The repo must run from the README setup. A hosted version is optional and must never need a judge's own accounts.

## 2. Non-negotiable rules (breaking one can disqualify the project)

The full rule list, each with its source and level, is `docs/private/hackathon-rules.md`; this section is the short form.

1. **New work only.** There is no pre-existing work: the repo was started fresh on Oct 27, 2026, the day after the hackathon began, and everything in it is event work. Never copy in code written before Oct 26 or from other projects. `PRIOR_WORK.md` says None. Third-party libraries (MapAnything, etc.) are dependencies, never copied in; they go in `THIRD_PARTY.md`.
2. **Public repo, Apache-2.0.** Record every model and asset licence in `THIRD_PARTY.md`.
3. **Demo only what we built.** No mock data presented as real; sample or illustrative data is labelled in UI and docs.
4. **Recall must never look like a banned project:**
   - Simple image analyzer → our value is 3D memory over time + guiding a person.
   - Basic RAG / chat wrapper → **geometry decides facts, the model only phrases them.** An LLM never infers locations from text labels.
   - Dashboard as main feature → the 3D viewer is a demo aid; the product is voice + guidance.
   - **No Streamlit** anywhere.
   - Medical advice → describe Recall as independence and accessibility, never health or vision care.
5. **No secrets in git.** `.env` is gitignored. The key list (`.env.example`) is kept locally in `docs/private/`, not committed.
6. **Privacy.** Never commit raw walkthrough video or frames. `samples/` holds only processed, reviewed data with nothing personal.
7. **Never invent APIs.** For Meta APIs, Muse Spark Open, Muse Glimmer, SAM 3.1, MapAnything, Baseten, Modal, Fireworks, LM Studio, R2 and ARKit, check official docs or model cards. If unverifiable, stop and ask, or leave `TODO(verify): ...` and report it.
8. **Meta models only at runtime** (organizer ruling). Every model the product calls at runtime is a Meta model: hosted on the Meta Model API, or open weights run by us on the Mac, Modal, Fireworks or Baseten. OS and browser features that are not model calls are fine (ARKit, LiDAR, haptics, VoiceOver, AVSpeechSynthesizer, Web Speech). **No non-Meta model anywhere, and no TTS model of any kind.** Which models count as Meta models follows the organizer rulings in `docs/private/hackathon-rules.md` (rule 1.2, Oct 31): check it before adding any model. Fine-tuning Meta models is allowed; any weights we present as ours must be public.

## 3. Stack

| Layer | Choice | Runs on |
|---|---|---|
| Guide LLM, `LLM_PROVIDER=baseten_spark_open` (**default**) | **Muse Spark Open** (`meta-models/muse-spark-open-1026`), OpenAI-compatible | **Baseten** (hackathon key) |
| Guide LLM, `LLM_PROVIDER=glimmer_hosted` | **Muse Glimmer**, OpenAI-compatible | **Modal** or **Fireworks**; Baseten if the credit allows |
| Guide LLM, `LLM_PROVIDER=lmstudio` (development, privacy mode) | Muse Glimmer 4-bit GGUF + vision projector | **LM Studio** local server on the Mac |
| Guide LLM, `LLM_PROVIDER=meta` (fallback) | Muse Spark, hosted | **Meta Model API** |
| Verifier vision tie-break | **Muse Spark 1.1** (multimodal); may only downgrade a result to `uncertain` | Meta Model API |
| Segmentation | **SAM 3.1** (objects **and** furniture by text prompt) | **Meta Model API** by default; optional self-hosted adapter on **Modal** for batch scan processing |
| Inbound screening | **Schema validation** (one object name: letters, digits, spaces, hyphens, max 40) then **Muse Spark Open** (or Glimmer) behind the `PromptScreener` port, strict JSON verdict, fails closed; every inbound A2A request, before any tool runs. | Baseten (LM Studio for Glimmer) |
| Speech to text | **Muse Voice Transcribe** only, using its turn detection (no Apple on-device speech recognition) | Meta Model API |
| Speech out | **AVSpeechSynthesizer** (iOS), **Web Speech `speechSynthesis`** (web): OS features, not models | device / browser |
| Fine-tuning (stretch only, not now) | Glimmer LoRA; the adapter is published if ever used | Modal |
| 3D reconstruction | **MapAnything**, weights **`facebook/map-anything-apache`** (Apache-2.0, HF revision `00f9c24`); VGGT fallback. Git dependency of `services/pipeline` pinned to commit `3d10cf7` (v1.1.4); torch installed separately for MPS | **Mac GPU (MPS) first**; if too slow, **Modal** (credits available), then a custom deployment on Baseten |
| Backend | Python 3.12, uv, FastAPI, Pydantic v2, SQLite, SQLAlchemy Core, Alembic | Mac, reachable from the phone through **Cloudflare Tunnel** |
| 3D maths | NumPy, SciPy, Open3D, trimesh | backend / pipeline |
| Scan storage | **Cloudflare R2** (S3-compatible multipart); local disk adapter for development | Cloudflare |
| iPhone app | Swift 6, SwiftUI with Liquid Glass per Apple's adoption guide (light canvas and white cards in old-Facebook blue; glass only on system bars, buttons and the scan HUD), ARKit (LiDAR depth, ARWorldMap), AVSpeechSynthesizer, background URLSession, **XcodeGen** | iPhone 16 Pro, iOS 26+ |
| Watch app | SwiftUI, WatchConnectivity, haptics (stretch goal) | Apple Watch Ultra 4; minimum watchOS `TODO(verify)`: the Ultra 4 ships with a current watchOS, so the deployment target can be the latest major; confirm against Apple's docs and the iPhone pairing requirement |
| Web | Next.js 16, React 19, TypeScript strict, **GSAP + `@gsap/react`** (scroll), **Motion** (UI), react-three-fiber (viewer). **No login anywhere**: the landing page, the sample room and the demo work signed out; judges never need an account | Vercel + GitHub Pages mirror |
| Multi-agent | Guide + Verifier + Home Memory agent; **A2A 1.0** via `a2a-sdk` (JSON-RPC), see `docs/private/agents.md` | inside the FastAPI app |
| Quality | ruff, pytest, import-linter, Schemathesis, ESLint, GitHub Actions, CodeQL (Python + TypeScript) | GitHub |

**Memory rule on the 48 GB Mac (M5 Pro):** never run MapAnything and LM Studio (Glimmer) at the same time. Qwen stays off.

All four Guide providers speak the OpenAI chat-completions format; the agent picks one with
`LLM_PROVIDER=baseten_spark_open|glimmer_hosted|lmstudio|meta`. Swapping is a change in `infra/container.py` driven by config.

**Run modes:** `make demo` replays a recorded sample scan and recorded model responses from `samples/replay/` with no keys,
clearly labelled as recorded output; `make live` makes real Meta model calls with keys from `.env`.

## 4. Architecture

**Hexagonal architecture (ports and adapters)**, with DDD for the domain model.

Two paths, **one writer**: only `services/api` writes the memory store (SQLite).
- **Scan path (async, minutes):** iPhone records an episode → chunked upload to R2 → manifest arrives → API triggers the pipeline →
  `services/pipeline`: MapAnything (fed ARKit intrinsics, poses and LiDAR depth as metric inputs) → floor and wall planes → SAM 3.1 masks
  (objects and furniture) → fuse into 3D objects → **`POST /scans/{id}/results`** → the API's `ingest_scan` use case writes the room model, landmarks and observations.
- **Query path (live, target under 2 s to first spoken words):** voice → Muse Voice Transcribe → agent use case (tools only) → spatial relations from geometry → route → spoken clock-face steps + Watch haptics.

### Dependency rule (enforced by import-linter in CI)

```
domain  ←  application  ←  adapters (inbound + outbound)
                        ←  infra (composition root, plumbing)
```

- `domain` imports nothing from other layers. No FastAPI, SQL, HTTP or LLM types.
- `application` imports `domain` only, and talks to the outside world through ports.
- `adapters` and `infra` may import inward; nothing imports them except `infra/container.py`.
- import-linter has two contracts per service: a **layers** contract (above) and a **forbidden** contract that stops
  `domain` and `application` importing `fastapi`, `sqlalchemy`, `httpx`, `openai`, `torch` and `boto3`.
  NumPy and SciPy are allowed in `domain` (spatial and navigation maths).
- Pydantic models generated from the spec live in `adapters/inbound/http` and never reach `application`.

### Domain model (DDD)

- **Aggregates** (each with one repository in `domain/ports.py`):
  - `Home`: floor plane and landmarks;
  - `Scan`: status, keyframes, transform to home;
  - `TrackedObject`: label, aliases, observations.
- **Value objects** (frozen dataclasses): `Position`, `Pose`, `HeightBand`, `Relation`, `RouteStep`.
- Entities are plain dataclasses: no base classes, generic repositories or event buses.

### Ports

- **API `domain/ports.py`** (one repository per aggregate): `HomeRepository`, `ScanRepository`, `TrackedObjectRepository`.
- **API `application/ports.py`** (needs of use cases): `LlmProvider`, `VisionProvider` (Muse Spark 1.1, tie-break only), `Transcriber`, `BlobStore`,
  `PipelineTrigger`, `Clock`, `Segmenter` (SAM 3.1 over HTTP on the Meta API, for the Verifier), `ArrivalVerifier`,
  `PromptScreener` (Muse Spark Open or Glimmer, after schema validation).
- **Pipeline `application/ports.py`**: `Reconstructor`, `Segmenter`, `EpisodeSource` (reads from R2 or disk), `ResultSink` (posts to the API).
  **torch and local models live only in the pipeline**; the API reaches vision models over HTTP only.

Ports are `typing.Protocol` classes. Swapping Baseten / Modal / Fireworks / LM Studio / Meta API is a change in `infra/container.py` driven by config, nothing else.

### Data model (SQLite, metres, home frame: floor z = 0, z up)

- `homes(id, name, floor_plane, room_model, created_at)`   room_model = the room.json below
- `scans(id, home_id, captured_at, status, transform_to_home, manifest_uri)`
- `keyframes(id, scan_id, ts, image_uri, depth_uri, pose_4x4, tracking_state)`
- `landmarks(id, home_id, label, bbox_min, bbox_max, centroid, room, front_dir)`
- `objects(id, home_id, label, aliases)`
- `observations(id, object_id, scan_id, keyframe_id, ts, position, height_m, confidence, crop_uri)`
- view `last_seen`: newest observation per object with confidence ≥ 0.5

### Spatial relations (`domain/spatial`, never the LLM)

- `on`: object base within 5 cm of a landmark's top surface and inside its footprint; shelves split into levels by height.
- `left_of / right_of`: relative to the landmark's `front_dir`.
- Height bands: floor < 0.3 m, knee 0.3 to 0.7, waist 0.7 to 1.1, chest 1.1 to 1.5, head > 1.5.
- Nearest landmark within 1.5 m, else room only.
- Thresholds live in `config/spatial.yaml`, tuned on real scans.

### Agent (`application/ask_where_is.py`)

Tools, defined once in `resources/tools.json`:

| Tool | Input | Returns |
|---|---|---|
| `find_object` | name | matches with label + last-seen time, or `not_found` |
| `describe_location` | object_id | room, landmark, relation, shelf level, height band, minutes since seen |
| `localize` | session_id | user position + facing in the home frame, `tracking_state` |
| `plan_route` | from_pose, object_id | ordered steps: clock-face turn + metres |

Grounding rules (system prompt **and** enforced in code):
1. Never state a place, distance or time that no tool returned.
2. `not_found` or confidence < 0.5 → say it hasn't been seen; suggest which room to walk through.
3. Sighting older than 24 h → say when it was seen.
4. `tracking_state = limited` → landmark directions only, and say so.
5. Spoken style: one or two short sentences; landmark first, then shelf and height, then time.
6. Max 6 agent steps; on failure give the best grounded partial answer.

### Multi-agent (full design in `docs/private/agents.md`)

- **Guide** (above) is the lead agent and the only one on the live question path.
- **Verifier** confirms arrival from one camera frame: SAM 3.1 + geometry decide; **Muse Spark 1.1** (hosted, multimodal) is asked only as a tie-break and may only downgrade to `uncertain`, never confirm.
  It is an API use case, so its memory updates (self-healing) keep the one-writer rule. Reached through the `ArrivalVerifier`
  port: **in-process by default and in the live demo**; over **A2A** optional (`VERIFIER_TRANSPORT`).
- **Home Memory agent** exposes read-only skills to external agents over **A2A**, off by default, never the user's live position.
  Inbound input is structured only (one object name, validated against `resources/agents/find-object.input.schema.json`; free
  text never reaches a model or a tool), then the `PromptScreener` port (**Muse Spark Open** or Glimmer, strict JSON, fails closed).

### Room model (`pipeline/domain/room_model.py`, no Apple room scanning)

Apple's room-scanning framework is not used (its scene understanding is a non-Meta model). The pipeline builds the room from the
MapAnything point cloud with classic geometry only (no ML modules of any library; Open3D-ML, OpenCV DNN and trained scikit-learn
models are banned):

1. **Clean-up (Open3D):** voxel downsample, then statistical outlier removal; thresholds in `config/spatial.yaml`.
2. **Planes (Open3D `segment_plane`, RANSAC, seeded):** floor first (largest near-horizontal plane, z up), then walls (near-vertical
   planes). Unit test: walls within 10 cm on a synthetic room (floor + 4 walls + noise).
3. **Furniture and objects (SAM 3.1 text prompts** `sofa`, `table`, `shelf`, `tv`, `bed`, `door` **+ objects):** each mask is lifted
   into 3D per frame, then **`cluster_dbscan` per label** merges the sightings, so one mug seen in 30 frames becomes one object with
   one centroid and one confidence.
4. **2D geometry (Shapely):** floor outline polygon, wall segments and furniture footprints, used for `room.json` and the occupancy grid.
5. **Later scans:** global registration (FPFH + RANSAC) then ICP into the first scan's frame, with Open3D, never hand-rolled.
   Umeyama stays for ARKit ↔ MapAnything poses.

Result: `room.json` = floor polygon, wall segments, furniture boxes, validated against `schemas/RoomModel.yaml`; written by
`ingest_scan`, served by **`GET /homes/{id}/room`**, and rendered on the phone with RealityKit (floor, extruded walls, boxes, pin, route).

**Blurry frames** are dropped on the phone (Laplacian variance with Accelerate, no third-party package) and checked again in the
pipeline with OpenCV classic functions (`opencv-python-headless`); same measure, thresholds in `config/spatial.yaml` (ADR-023).

**Moved objects (`application/ingest_scan.py`):** when a new scan arrives, objects of the same label are matched to the previous scan
with `scipy.optimize.linear_sum_assignment` on 3D distance; unmatched, or moved more than 30 cm, becomes a new observation and the old
one is marked stale. Unit test: two synthetic scans, one object moved, one gone.

**Debugging (`RERUN=1`, dev only):** `process_episode` logs camera poses and frustums, keyframes, LiDAR depth, the point cloud, SAM
masks, lifted objects, fitted planes, the occupancy grid and the planned route to the Rerun viewer on one timeline; `make rerun
EPISODE=<path>` replays a stored episode. Off by default; never required for tests or `make demo`.

### Navigation (`domain/navigation`)

Occupancy grid from the point cloud (10 cm cells; obstacles = points 0.1 to 1.8 m above floor). **Clearance** per cell from
`scipy.ndimage.distance_transform_edt`; obstacles are **inflated by a body radius** (config, default 0.3 m) and cells near obstacles
cost more, so A* keeps to the middle of free space. A* to a reachable cell near the object, path simplified to turns, converted to
clock-face steps, updated as the ARKit pose changes. If no cell path is wider than the body, the planner reports **"no safe path"**
and the Guide falls back to landmark directions. Unit tests: a synthetic corridor (path stays centred) and a narrow gap (no safe path).

### Frame alignment (`pipeline/domain/align.py`)

MapAnything accepts metric inputs per view (`intrinsics`, `depth_z`, `camera_poses`, `is_metric_scale`), so the pipeline
feeds it the ARKit intrinsics, poses and LiDAR depth. Its output is then already in the ARKit world frame, in metres.

- Pose convention: MapAnything wants **OpenCV cam2world** (+X right, +Y down, +Z forward). ARKit's camera is +Y up,
  −Z forward, so `T_opencv = T_arkit @ diag(1, −1, −1, 1)`. This has a unit test.
- If any view has a pose, the first view must too.
- **Umeyama** similarity transform (ARKit vs MapAnything camera centres) is the **check and fallback**: it measures drift,
  and aligns an images-only run if ARKit inputs are missing.
- Later scans align to the first with Open3D (global registration, then ICP).

## 5. Scan episodes and upload

Each walkthrough is an **episode**, not a video:

```
scan-<uuid>/                       uuid created on the phone → retries are idempotent
  manifest.json                    device, intrinsics scaled to the saved frame size, depth size + units, frame count,
                                   duration, app version, sha256 per file, capture_metrics
  frames/000123.jpg                long edge ≈ 1024 px, aspect kept (MapAnything resizes to its 518 px set; SAM uses full size)
  depth/000123.png                 LiDAR depth, 16-bit millimetres, native LiDAR resolution
  confidence/000123.png            ARKit depth confidence, 0 to 2
  poses.jsonl                      per frame: timestamp, ARKit camera-to-world pose 4x4 (column-major, ARKit camera
                                   convention; the pipeline converts with arkit_to_opencv()), tracking state + reason
```

Capture rules (on the phone):
- Plain ARKit on our own `ARSession`: **no `sceneReconstruction`, no plane classification** (those are Apple models).
- Keyframe when the phone moved ~15 cm or turned ~10° (about 2 per second); drop blurry frames.
- "Slow down" coaching from `ARCamera.trackingState` reasons (`excessiveMotion`, `insufficientFeatures`) plus our own speed and
  turn-rate limits computed from the pose. Metrics and the Good / Usable / Redo report stay.
- Limits: 10 s to 3 min per room, under 200 MB per episode; reject with a spoken reason otherwise.

Upload (resumable):
- Presigned **multipart** upload to R2 via background `URLSession`; parts of ~8 MB (S3 minimum part size is 5 MB except the last).
- Each part checksummed; failed parts retry alone.
- **`manifest.json` uploaded last**; `POST /scans/{id}/complete` validates it and triggers the pipeline.
- No live video streaming: scans are batch; live guidance runs on the phone.

Recorded episodes double as **regression tests**: re-run the pipeline on stored episodes and compare object positions to the last good run.

## 6. Repository structure

```
recall/
├── README.md                       theme, models table with code paths, try-it, video, architecture
├── CLAUDE.md                       this file
├── LICENSE                         Apache-2.0
├── THIRD_PARTY.md                  models, fonts, images + licences
├── PRIOR_WORK.md                   "None.": the repo was started fresh on Oct 27, 2026
├── Makefile
├── .github/workflows/           ci.yml (ruff, pytest, import-linter, web typecheck/lint/build), codeql.yml (Python + TypeScript)
├── apps/
│   ├── ios/                        see docs/private/ios-ARCHITECTURE.md: RecallKit package + thin Recall / RecallWatch targets
│   └── web/
│       ├── app/(marketing)/        landing page (finished; keep as it is)
│       ├── app/(app)/              homes/[homeId], homes/[homeId]/viewer (that home's scan from public/local-scan/<home>/, gitignored; no auth)
│       ├── components/scroll/      GSAP-owned
│       ├── components/ui/          Motion-owned
│       ├── components/viewer/      react-three-fiber
│       └── lib/                    gsap.ts, motion-prefs.tsx, site.ts, api.ts
├── services/
│   ├── api/
│   │   ├── pyproject.toml
│   │   ├── alembic.ini
│   │   ├── resources/              API contract, spec-first (source of truth)
│   │   │   ├── openapi.yaml        root: info, servers, $refs only
│   │   │   ├── paths/              scans.yaml, ask.yaml, guidance.yaml (+ verify), objects.yaml, homes.yaml (room), voice.yaml (transcribe)
│   │   │   ├── schemas/            Scan, Episode, Pose, ScanResult, RoomModel, ObjectLocation, Answer, RouteStep, VerificationResult, Error
│   │   │   ├── agents/             verifier.card.json, home-memory.card.json (A2A Agent Cards)
│   │   │   └── tools.json          agent tool schemas
│   │   ├── db/migrations/          Alembic revisions, plain SQL inside
│   │   ├── src/recall_api/
│   │   │   ├── domain/
│   │   │   │   ├── memory/         aggregates Home, Scan, TrackedObject (+ Landmark, Keyframe, Observation)
│   │   │   │   ├── spatial/        Relation, HeightBand, relate()
│   │   │   │   ├── navigation/     FloorGrid, astar(), to_clock_steps()
│   │   │   │   ├── assistant/      GroundedAnswer, grounding rules
│   │   │   │   └── ports.py        repositories only
│   │   │   ├── application/
│   │   │   │   ├── ports.py        LlmProvider, VisionProvider, Segmenter, Transcriber, BlobStore, PipelineTrigger, Clock, ArrivalVerifier, PromptScreener
│   │   │   │   ├── ingest_scan.py  writes pipeline results (the only writer)
│   │   │   │   ├── ask_where_is.py agent loop
│   │   │   │   ├── localize_user.py
│   │   │   │   ├── plan_guidance.py
│   │   │   │   └── tools.py        tool registry, validated against resources/tools.json
│   │   │   ├── adapters/
│   │   │   │   ├── inbound/http/   FastAPI routers: mapping only, no logic
│   │   │   │   ├── inbound/a2a/    verifier_server.py, home_memory_server.py
│   │   │   │   └── outbound/
│   │   │   │       ├── agents/     verifier_a2a_client.py, verifier_inprocess.py
│   │   │   │       ├── vision/     sam31_meta_api.py, spark_vision_meta_api.py (HTTP only)
│   │   │   │       ├── safety/     meta_model_screen.py (Muse Spark Open or Glimmer, strict JSON verdict)
│   │   │   │       ├── llm/        openai_compatible.py (+ baseten_spark_open, glimmer_hosted, lmstudio, meta configs)
│   │   │   │       ├── replay/     recorded_llm.py, recorded_segmenter.py (make demo)
│   │   │   │       ├── voice/      muse_transcribe.py
│   │   │   │       ├── storage/    r2_multipart.py, local_disk.py
│   │   │   │       └── persistence/ sqlite repositories (SQLAlchemy Core)
│   │   │   ├── infra/              db.py, container.py (composition root), logging.py, app.py (FastAPI factory, Swagger UI)
│   │   │   ├── config/             settings.py (pydantic-settings), spatial.yaml
│   │   │   └── util/               ids, retry: generic only (time comes from the Clock port)
│   │   └── tests/
│   │       ├── unit/               domain + application with fake adapters
│   │       ├── contract/           API vs openapi.yaml (Schemathesis); tools.json vs registry
│   │       └── integration/        SQLite + local disk; external APIs behind RUN_EXTERNAL=1
│   └── pipeline/                   same layering, smaller; rerun-sdk as a dev dependency only (RERUN=1 logs the whole run on one timeline)
│       ├── scripts/                export_viewer_points.py: run output → viewer sample (points, colours, confidence, flat surfaces)
│       └── src/recall_pipeline/
│           ├── domain/             Episode, Frame, Pose, arkit_to_opencv(), align.py (Umeyama check/fallback), room_model.py (planes, Shapely 2D geometry), merge.py (per-label clustering), blur.py
│           ├── application/        process_episode.py, ports.py (Reconstructor, Segmenter, EpisodeSource, ResultSink)
│           └── adapters/           mapanything_local.py, mapanything_remote.py, sam31_meta_api.py, sam31_modal.py (optional), open3d_geometry.py (clean-up, segment_plane, DBSCAN, FPFH+ICP), rerun_log.py, storage, api_client.py
├── deploy/
│   ├── baseten/README.md           Spark Open: hosted endpoint, key only
│   ├── modal/glimmer/              Glimmer serving (TODO(verify) Modal API); fireworks/ alternative
│   ├── modal/sam31/                optional self-hosted SAM 3.1 for batch scans
│   ├── modal/mapanything/          only if the Mac is too slow
│   └── lmstudio/README.md          model file, settings, server command
├── evals/
│   ├── questions.yaml              id, utterance, expected object, expected relation, must_not_say
│   ├── episodes/                   pointers to stored regression episodes (no raw video in git)
│   ├── run.py
│   ├── verifier.yaml               20 arrival frames: 10 right spot, 10 wrong spot
│   └── results.md                  dated accuracy table
├── examples/a2a-client/home_robot.py  external agent asking Recall over A2A (Muse Spark)
├── samples/replay/                 recorded scan + recorded model responses for `make demo` (labelled as recorded)
└── docs/                           (docs/private/ is gitignored: planning docs, ADRs, progress notes, the key list)
    ├── architecture.md             hexagon diagram + both paths (mermaid)
    ├── verification.md             answers to section 10, with sources
    ├── demo-script.md
    └── media/                      README images: our own captures only (logo.svg, hero, viewer, gather); no photos of the home
```

## 7. Conventions

- **Python:** 3.12, uv, type hints everywhere, ruff (lint + format), pytest. Entities are dataclasses. No base classes, generic repositories or event buses. One file per use case. Unit tests never touch the network.
- **Spec-first API:** edit `resources/` first. Pydantic models generated with `datamodel-code-generator`; Swift client with `swift-openapi-generator`; bundle with Redocly CLI. Swagger UI at `/docs` serves the real spec.
- **Swift:** Swift 6, SwiftUI, async/await, no third-party packages unless asked. Every control has an accessibility label; everything usable with VoiceOver and without looking.
- **Web:** GSAP owns scroll storytelling, Motion owns UI state; **never both on one element**. Viewer data is binary (Float32 positions + Uint8 colours, voxel-downsampled, under 2 MB; the host serves it Brotli-compressed); JSON only for `room.json` and objects. Phase 4, if phases 1 to 3 are done: `@react-three/drei` (orbit controls, labels pinned to objects) and `postprocessing` (outline) for a "High contrast" viewer toggle: thick dark outlines where depth jumps, a small palette, larger labels, reduced motion respected, WCAG 2.2 AA. `useGSAP()` in `"use client"` components; plugins registered once in `lib/gsap.ts`. Reduced motion respected by both libraries and the site's toggle. Content visible without JavaScript; no long scroll-jacking. Self-hosted fonts and images.
- **Accessibility:** WCAG 2.2 AA minimum, body text aims for 7:1. Tokens live in `apps/web/app/globals.css` (source of truth):
  fb-blue #3b5998, fb-blue-dark #29487d, fb-blue-pale #dfe3ee, fb-grey #f0f2f5, fb-line #bdc7d8, ink #1c1e21, muted #4b4f56,
  cta #42b72a / cta-dark #1f6516, a warm gradient ring #feda75 → #4f5bd5 (decoration only). A high-contrast theme swaps them.
  The look is a deliberate 2008 social-network homage (ADR-014): no Meta, Facebook or Instagram logos, wordmarks or current
  brand styling anywhere, and the footer says "not affiliated". The landing page is finished; don't restyle it.
- **Commits:** small, frequent, Conventional Commits. Timestamps are our evidence of when work happened.
- **Decisions:** any trade-off gets a 5-line ADR in `docs/private/decisions.md`.

### Make targets

`setup dev demo live probes rerun test lint lint-imports migrate bundle-spec gen-models gen-swift-client eval`

- `demo`: replay from `samples/replay/`, no keys, output labelled as recorded. `live`: real Meta model calls with `.env`.
- `probes`: one small real call per external model or service (Meta Model API, Baseten Spark Open, Muse Voice Transcribe, SAM 3.1,
  R2) that prints what worked and appends the result to `docs/verification.md`; needs `.env`; never run in CI.
- `rerun EPISODE=<path>`: replay a stored episode into the Rerun viewer (`RERUN=1`); dev only, never needed for tests or `make demo`.

## 8. Definition of done (every task)

1. `make test`, `make lint`, `make lint-imports` green.
2. No secrets, no raw home video, no unverified API usage without `TODO(verify)`.
3. Spec, README or docs updated if behaviour changed.
4. Summary to the user: what changed, how to run it, what is still unverified.

## 9. Phases (Europe/Warsaw)

| Phase | Dates | Goal | Done when |
|---|---|---|---|
| 0 Scaffold | Oct 29 to 30 | Repo, hexagonal skeleton, spec, migrations, CI | `make setup && make test` green; CI green |
| 1 Scan spike + iPhone Scan | Oct 30 to Nov 1 | Full iPhone Scan feature (plain ARKit episode capture, SpeedCoach, metrics, scan report, upload, professional UI); one room episode with ARKit inputs → plane fitting → `room.json` + 3D objects in metres | Objects within ~20 cm of reality on an ARKit-input run (**go/no-go**). Runs alongside phase 2; about 8 to 11 h of iOS work |
| 2 Memory + agent | Oct 31 to Nov 1 | Memory, spatial relations, Guide agent (Spark Open) with tools | 30-question eval runs; answers only from tool output |
| 3 Guidance | Nov 1 to 2 | Find, ask, live ARKit guidance, voice; Watch; **Verifier (in-process)** | Walk to an object with eyes closed; arrival confirmed on camera |
| 4 Proof | Nov 2 to 3 | Viewer, real output on landing page, eval results, sample scan, `samples/replay/`; **A2A servers + schema validation and Meta-model screening + `home_robot.py` demo** | `make demo` works without GPU or keys; verifier precision ≥ 0.9 on 20 frames |
| 5 Ship | Nov 3 to 4 | README ("What runs where"), 3-minute video, X post, submission, rehearsal | Submitted before Nov 4 evening Warsaw; tag `submission` |

**Schedule:** phases keep their dates; we work overtime (evenings) to finish each one on time rather than cut scope.
The "Cut if late" lists in `docs/private/agents.md` stay as a last resort.

Fallbacks: phase 1 misses → VGGT or LiDAR depth only. Live guidance unstable → landmark directions only (must always work alone).

## 10. Verification checklist

Nothing below is confirmed. **Claude Code**: check what you can from official docs and record the answer and source
link in `docs/verification.md`. **Rachit**: items marked "You" need accounts or devices. Update the status column as items close.

### Access and APIs

| # | Check | Who | How | If it fails |
|---|---|---|---|---|
| 1 | Meta Model API works from Poland with our key | You | One chat-completion call | Ask in Discord office hours; Spark Open on Baseten only |
| 2 | ✅ mostly (see verification.md; mask encoding still open). SAM 3.1 on Meta API: input modes (single image, batch, **video tracking across frames**), text prompts, mask format (RLE, PNG, polygons), rate limits, cost per call | Claude Code (docs) + You (test call) | Docs + one call with 3 frames | Self-hosted SAM 3.1 adapter on Modal (open weights) |
| 3 | Muse Voice Transcribe: endpoint, audio formats, sample rate, batch vs streaming, **turn detection**, latency | Claude Code + You | Docs + one 5 s m4a | Push-to-talk without turn detection; typed question as last resort (no Apple on-device speech recognition) |
| 4 | Hosted Muse Spark model ID on Meta API, tool-calling support; **Muse Spark 1.1 image input** for the Verifier tie-break | Claude Code + You | Docs + one tool call + one image call | Drop the cloud fallback / the tie-break |
| 5 | Muse Glimmer: HF repo id (`meta-models/Muse-Glimmer-30B`?), gating, licence, minimum vLLM version, **tool-call parser name**, chat template, image input format; **hosting on Modal or Fireworks** | Claude Code | Model card, Modal / Fireworks docs | Guide stays on Spark Open |
| 6 | Baseten: **Spark Open** (`meta-models/muse-spark-open-1026`) endpoint URL format, **tool calling and latency**; whether the hackathon credit can also serve Glimmer | You | One tool call + timing | `glimmer_hosted` on Modal / Fireworks |
| 7 | LM Studio: Glimmer GGUF + vision projector loads; **tool calling works** via `/v1/chat/completions`; memory used | You | One tool-call request | Develop against Spark Open on Baseten instead |
| 8 | MapAnything: repo, licence, installs on macOS with Apple GPU, input size, metric scale output, **time and memory per room on M5 Pro** | ✅ | `docs/verification.md`: 63 frames → 19.6 s inference, 14.8 GB peak on MPS; images-only scale ~23 % too large (fails 20 cm), shape OK → go/no-go needs a run with ARKit inputs | VGGT; Modal; Baseten custom deployment |
| 9 | ~~Modal credits~~ ✅ Rachit has Modal credits (2026-10-29) | You | n/a | Baseten for MapAnything |
| 10 | R2 multipart: part size limits, presigned URL expiry, max parts | Claude Code | Cloudflare docs | Local disk + tus-style resume |
| 10a | ✅ Inbound screening: schema validation + Muse Spark Open strict-JSON verdict on Baseten; measured in `docs/verification.md` | Claude Code | Live run | Glimmer on LM Studio |
| 10b | **Plane fitting gives walls within 10 cm on the first real scan** (ARKit-input run) | You + Claude Code | Tape-measure two walls vs `room.json` | Floor only; walls from the occupancy grid |

### Devices

| # | Check | Who | How | If it fails |
|---|---|---|---|---|
| 11 | ARKit LiDAR depth resolution and rate; pose quality while walking; `trackingState` reasons fire as expected | You | Test capture | RGB only, MapAnything depth |
| 12 | ARWorldMap save/relocalise reliability in our flat | You | Relocalise 5 times from different spots | Photo-based relocalisation via keyframe match |
| 13 | Free Apple ID can install the Watch app; 7-day expiry date noted | You | Install both apps | Skip Watch; voice only |

### Hackathon

| # | Check | Who | How | If it fails |
|---|---|---|---|---|
| 14 | Submission form fields ✅ known: team, track, problem statement, X link, description, repo, video, Meta usage, why Meta, partner feedback, two survey questions | You | Fill it in early; keep the texts in `docs/demo-script.md` | n/a |
| 15 | Rubric criteria (if published) → adjust priorities | You | Discord / form | Keep current weights |
| 16 | Bonus prizes: ✅ no bonus checkboxes in the form; only Most Viral takes a link (the X post); open-weights use is verified by the partner. Still open: can one project win several | You | Ask in Discord | Prioritise open weights + agentic |
| 17 | Live final time on Nov 9 in Warsaw time | You | Discord | n/a |

### Licences and privacy

| # | Check | Who | How | If it fails |
|---|---|---|---|---|
| 18 | Licences: Muse Spark Open, Glimmer, Muse Spark 1.1 (hosted terms), SAM 3.1, ~~MapAnything~~ (✅ code and `map-anything-apache` weights Apache-2.0), VGGT, Atkinson Hyperlegible font; new libraries before first use: rerun-sdk, Shapely, opencv-python-headless, `@react-three/drei`, `postprocessing` (~~GSAP~~ ✅ checked) | Claude Code | Model cards, licence files | Replace the component |
| 19 | Samples and media contain nothing personal (documents, screens, addresses, people) | You | Manual review before every commit to `samples/` or `docs/media/` | Blur or drop |

### Multi-agent and A2A

See `docs/private/agents.md` section 8 (items A1 to A7): `a2a-sdk` API, Agent Card discovery path and required fields in spec 1.0,
SAM 3.1 single-frame latency, Muse Spark 1.1 image input, mounting A2A routes in FastAPI, inbound screening.

### Tooling versions

| # | Check | Who | How | If it fails |
|---|---|---|---|---|
| 20 | Python 3.12, uv, Node 22, Xcode (current), XcodeGen, swift-openapi-generator, datamodel-code-generator, Redocly CLI, Alembic, import-linter, Schemathesis install and run | Claude Code | `make setup` | Pin older working versions; note in README |
