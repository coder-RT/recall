# Third-party services, models and assets

What Recall uses that we didn't make, and on what terms. Every model called at runtime is a Meta model.
Library versions are pinned in the lockfiles (`pnpm-lock.yaml`, `uv.lock`).

## Meta models and services

| What | Used for | Runs on | Terms |
|---|---|---|---|
| Muse Spark Open (`meta-models/muse-spark-open-1026`) | Guide agent; the Home Memory agent's check on object names from other agents | Baseten | TODO(verify): model licence, link |
| Muse Glimmer | Guide agent, local privacy mode | LM Studio on the Mac | TODO(verify): licence on the Hugging Face model card, link |
| Muse Spark (hosted) and Muse Spark 1.1 | Guide fallback; Verifier tie-break | Meta Model API | Meta developer terms. TODO(verify): link |
| SAM 3.1 | Objects and furniture in frames; arrival check | Meta Model API | Meta developer terms. TODO(verify): link; weights licence if self-hosted |
| Muse Voice Transcribe (`muse-voice-transcribe-1.0`) | All speech input (app and the landing page's "Ask by voice", server route `apps/web/app/api/voice/transcribe/route.ts`; the key never reaches the browser) | Meta Model API | Meta developer terms. Audio is forwarded for transcription and not stored by Recall. |
| MapAnything (`facebookresearch/map-anything` @ `3d10cf7`), weights `facebook/map-anything-apache` @ `00f9c24` | 3D reconstruction; produced the sample room in `apps/web/public/samples/demo-flat/` | Mac | Code Apache-2.0; weights Apache-2.0 (see `docs/verification.md`) |

## Our own artwork

| What | Where | Terms |
|---|---|---|
| Thing icons (keys, wallet, bag, backpack, book, bottle, glasses, phone, remote, mug, laptop, headphones, charger, watch, passport, and the box for unsure things) | `apps/ios/Recall/Resources/Assets.xcassets/Things`, drawn by `apps/ios/scripts/make_thing_icons.py` | Drawn for Recall; Apache-2.0 with the rest of the repo. No third-party art |

## Hosting and infrastructure

| What | Used for | Terms |
|---|---|---|
| Baseten | Hosts Muse Spark Open | Baseten terms of service |
| Modal | Optional GPU backup for MapAnything or SAM 3.1 | Modal terms of service (remove if unused) |
| Fireworks | Optional Glimmer hosting | Fireworks terms of service (remove if unused) |
| LM Studio | Runs Muse Glimmer locally | LM Studio terms |
| Cloudflare R2, Cloudflare Tunnel | Scan storage; reaching the Mac from the phone | Cloudflare terms of service |
| Vercel | Hosts the web app (optional) | Vercel terms of service |

## Libraries

Direct dependencies only. Licences below are as published by each project.

### Web (`apps/web`)

| What | Used for | Licence |
|---|---|---|
| Next.js | Web framework | MIT |
| `@vercel/firewall` 1.2.6 | The voice demo route asks Vercel's firewall rule `voice-transcribe` whether a visitor is over the limit | Apache-2.0 (npm `license` field, checked 2026-11-01). Used as an npm dependency. |
| React | UI | MIT |
| three.js (`three` 0.186.1) | Point-cloud rendering in the 3D viewer | MIT |
| react-three-fiber (`@react-three/fiber` 9.8.2) | React renderer for three.js (`apps/web/components/viewer/`) | MIT |
| `@react-three/drei`, `postprocessing` (phase 4 only, not yet added) | Viewer labels, orbit controls, outline effect for the high-contrast toggle | MIT; Zlib. TODO(verify) before adding: https://github.com/pmndrs/drei , https://github.com/pmndrs/postprocessing |
| GSAP, `@gsap/react` | Scroll storytelling (ScrollTrigger, SplitText, DrawSVG) | Standard "No Charge" GSAP License (Webflow; its own terms, not MIT): free for any website or web app, commercial included, no attribution required, keep its notices intact. https://gsap.com/community/standard-license/ (checked 2026-10-29). Used as an npm dependency, not copied into the repo. |
| Motion | UI animation | MIT |
| `@vercel/speed-insights` | Page-speed numbers (Core Web Vitals) on the Vercel deployment; no cookies | Apache-2.0 (npm registry, version 2.0.0, checked 2026-10-30), https://www.npmjs.com/package/@vercel/speed-insights |

### Python (`services/api`, `services/pipeline`)

| What | Used for | Licence |
|---|---|---|
| FastAPI, Uvicorn | HTTP API | MIT; BSD-3-Clause |
| OpenTelemetry Python (`opentelemetry-sdk`, `-instrumentation-fastapi`, `-instrumentation-httpx`, `-exporter-otlp-proto-http`) | Request and model-call traces | Apache-2.0 (package metadata checked 2026-10-30), https://github.com/open-telemetry/opentelemetry-python |
| Huey (`SqliteHuey`) | Scan job queue and nightly scheduler on the Mac | MIT (licence file in the 3.5.3 wheel, checked 2026-10-30), https://github.com/coleifer/huey |
| Pydantic, pydantic-settings | Models and config | MIT |
| SQLAlchemy, Alembic | Database access and migrations | MIT |
| NumPy, SciPy | 3D maths | BSD-3-Clause |
| Open3D (classic geometry only: downsample, outlier removal, `segment_plane`, `cluster_dbscan`, FPFH + ICP; never Open3D-ML), trimesh | Point clouds, planes, clustering, registration, meshes | MIT. TODO(verify) before first use: current API names, https://www.open3d.org/docs/ |
| Shapely | 2D room geometry: floor polygon, wall segments, footprints | BSD-3-Clause. TODO(verify): https://github.com/shapely/shapely |
| opencv-python-headless | Classic image functions only (Laplacian blur measure); never the DNN module | Apache-2.0 (OpenCV) / MIT (package). TODO(verify): https://github.com/opencv/opencv-python |
| Pillow | API: cuts the evidence crop from a stored keyframe (`GET /observations/{id}/crop`); pipeline: reads frames | MIT-CMU (HPND). TODO(verify): https://github.com/python-pillow/Pillow/blob/main/LICENSE |
| rerun-sdk (dev dependency of `services/pipeline` only) | Debug viewer for pipeline runs (`RERUN=1`, `make rerun`) | MIT or Apache-2.0. TODO(verify): https://github.com/rerun-io/rerun |
| a2a-sdk | Agent-to-agent protocol | Apache-2.0 |
| httpx | Calls to model APIs | BSD-3-Clause |

### iOS (`apps/ios`)

No third-party Swift packages. Apple frameworks only (ARKit, RealityKit, SwiftUI, AVFoundation, WatchConnectivity).

### Build and test tools (not shipped)

| What | Licence |
|---|---|
| uv, Ruff | MIT or Apache-2.0 |
| pytest, Schemathesis, datamodel-code-generator | MIT |
| Playwright, `@axe-core/playwright` | Apache-2.0; MPL-2.0 |
| `@types/three` | MIT |
| NumPy, SciPy (also used by `services/pipeline/scripts/export_viewer_points.py`) | BSD-3-Clause |
| import-linter | BSD-2-Clause |
| Redocly CLI | MIT |
| XcodeGen | MIT |
| swift-openapi-generator | Apache-2.0 |

Remove any row for a tool or library that isn't actually in the repo at submission.

## Fonts

| What | Licence |
|---|---|
| Atkinson Hyperlegible Next (via `next/font/google`, self-hosted at build) | SIL Open Font License 1.1 |

## Audio

None. Every spoken line on the site is the browser's own speech synthesis (`apps/web/lib/speech.ts`); no recording is
shipped and no speech model runs. Speech input is Muse Voice Transcribe (above).

## Images

All images in the repo and on the site come from our own scans and screenshots. No third-party images.
TODO(verify): confirm before submission; list any exception here with its licence.