<p align="center">
  <img src="docs/media/logo.svg" width="96" height="96" alt="Recall's mark: the Braille cell for R">
</p>

<h1 align="center">RECALL</h1>

<p align="center"><strong>Recall remembers where you put things, and walks you back to them.</strong><br>
<em>“Where did I put my keys?”</em></p>

<p align="center"><strong>Built during the Meta Global AI Developer Hackathon, Oct 26 to Nov 4, 2026. Pre-existing work: none.</strong><br>
Indie track · Theme: <strong>Build for Your World</strong></p>

<p align="center">
  <a href="https://github.com/coder-RT/recall/actions/workflows/codeql.yml"><img src="https://github.com/coder-RT/recall/actions/workflows/codeql.yml/badge.svg" alt="CodeQL"></a>
  <img src="https://img.shields.io/badge/licence-Apache--2.0-3b5998" alt="Licence: Apache-2.0">
  <img src="https://img.shields.io/badge/Next.js_16-000000?logo=nextdotjs&logoColor=white" alt="Next.js 16">
  <img src="https://img.shields.io/badge/React_19-20232a?logo=react&logoColor=61dafb" alt="React 19">
  <img src="https://img.shields.io/badge/three.js-000000?logo=threedotjs&logoColor=white" alt="three.js">
  <img src="https://img.shields.io/badge/Python_3.12-3776ab?logo=python&logoColor=white" alt="Python 3.12">
  <img src="https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white" alt="FastAPI">
  <img src="https://img.shields.io/badge/Swift_6-f05138?logo=swift&logoColor=white" alt="Swift 6">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/SAM_3.1-Meta_model-0467df?logo=meta&logoColor=white" alt="SAM 3.1">
  <img src="https://img.shields.io/badge/MapAnything-Meta_model-0467df?logo=meta&logoColor=white" alt="MapAnything">
  <img src="https://img.shields.io/badge/Muse_Spark_Open-Meta_model-0467df?logo=meta&logoColor=white" alt="Muse Spark Open">
  <img src="https://img.shields.io/badge/Muse_Glimmer-Meta_model-0467df?logo=meta&logoColor=white" alt="Muse Glimmer">
  <img src="https://img.shields.io/badge/Muse_Voice_Transcribe-Meta_model-0467df?logo=meta&logoColor=white" alt="Muse Voice Transcribe">
  <img src="https://img.shields.io/badge/Llama_Prompt_Guard-Meta_model-0467df?logo=meta&logoColor=white" alt="Llama Prompt Guard">
</p>

<p align="center">
  <a href="#how-to-run-it">Run it</a> ·
  <a href="#how-it-works-the-meta-models">How it works</a> ·
  <a href="#results-so-far">Results</a> ·
  <a href="https://www.linkedin.com/in/rachit-thariani/">LinkedIn</a> ·
  <a href="https://github.com/coder-RT">GitHub</a>
</p>

> Status: in progress during the hackathon. This README is updated as each part starts working; anything not yet
> working is listed under [Not in this submission](#not-in-this-submission).

---

## Contents

1. [What it is](#what-it-is)
2. [Why I built it](#why-i-built-it)
3. [Why agents](#why-agents)
4. [How it works: the Meta models](#how-it-works-the-meta-models)
5. [Guardrails](#guardrails)
6. [Algorithms](#algorithms)
7. [Results so far](#results-so-far)
8. [How to run it](#how-to-run-it)
9. [Not in this submission](#not-in-this-submission)
10. [Contributing](#contributing)
11. [Built during the hackathon](#built-during-the-hackathon)
12. [Licence](#licence)

## Screenshots

The landing page. No image of anyone's home is in this repo: the 3D viewer shows only a room you scan yourself.

![The landing page hero](docs/media/hero.png)

## What it is

**What**
- A voice-first 3D memory of your home for blind and low-vision people.
- Walk through a room once with an iPhone. Recall rebuilds the room in metres and remembers what it saw and where.
- Ask "where are my keys?" and hear the answer: which surface, which shelf level, how high, when it was last seen.
- Say "guide me there" and get clock-face steps as you walk, with taps on the Watch, and a camera check on arrival.

**Why**
- Finding small things is a daily, tiring problem when you can't see where they are.
- Existing tools describe a single photo. They don't remember, and they don't walk you there.
- Independence and accessibility, not care: Recall is a memory and a guide, nothing medical.

**How**
- The iPhone records frames, LiDAR depth and ARKit poses, and leads the scan by voice, step by step: turn round, walk the walls, sweep the floor, close the loop. It measures how much floor and wall the LiDAR saw and whether ARKit's room map is ready, and says when to slow down, step back, add light or tilt down. Meta's MapAnything turns the frames into a metric 3D map; SAM 3.1 finds the furniture and objects in every frame.
- Geometry decides the facts (floor, surfaces, height bands, distances). A Meta language model only phrases them.
- A small team of agents answers, verifies and shares; every model they call is a Meta model.

**Frameworks and stack**
- Web: Next.js 16, React 19, TypeScript, GSAP (scroll storytelling), Motion (UI), react-three-fiber (3D viewer).
- Backend: Python 3.12, FastAPI, SQLite, hexagonal architecture (ports and adapters) with DDD aggregates.
- Reconstruction pipeline: Python, MapAnything on the Mac's GPU, NumPy and SciPy for the geometry.
- iPhone and Watch: Swift 6, SwiftUI, ARKit, RealityKit, AVSpeechSynthesizer, WatchConnectivity.
- Models: Meta Model API, Baseten (Muse Spark Open), Modal or LM Studio for open weights.

## Why I built it

- The question "where did I put my keys?" is asked in every home, and for a blind person it can end a morning.
- A home barely changes; what moves are the small things. That calls for a memory of the space, not a smarter camera.
- The pieces now exist as open Meta models: metric 3D from photos (MapAnything), find anything by name (SAM 3.1), a language model that can call tools and phrase a short spoken answer (Muse Spark Open / Glimmer).
- I wanted the result measured on real objects in a real flat, with the numbers published, rather than demonstrated on slides.

## Why agents

- **Guide** is the only agent on the live question path. It calls four tools (`find_object`, `describe_location`, `localize`, `plan_route`) and phrases the answer. It never states a place, distance or time that no tool returned. Target: first spoken words within 2 seconds.
- **Verifier** runs once, on arrival: one camera frame, SAM 3.1 plus the LiDAR depth, and a yes or no on whether the object is really there. Muse Spark 1.1 can only lower confidence. If the object isn't there, the memory heals itself and the Guide says when it was last seen. The Guide calls it in-process by default and in the live demo; A2A between the two is optional.
- **Home Memory** is the house's face to other agents (a robot, a pair of glasses, another assistant) over the open A2A 1.0 protocol: read-only, off by default, never the user's live position, and every incoming message is screened by Llama Prompt Guard first.
- One rule: every agent has a job no other agent does. Complexity is not the goal; the three jobs are different.

## How it works: the Meta models

**Every model called at runtime is a Meta model.**

| Model | Job | Runs on | Code |
|---|---|---|---|
| Muse Spark Open (`meta-models/muse-spark-open-1026`) | Guide agent: calls tools, phrases the answer (default) | Baseten | `services/api/.../adapters/outbound/llm/` |
| Muse Glimmer | Guide agent alternative; local privacy mode | Modal / Fireworks; LM Studio on the Mac | same adapter |
| Muse Spark (hosted) | Guide fallback | Meta Model API | same adapter |
| Muse Spark 1.1 (multimodal) | Verifier tie-break; may only downgrade a result, never confirm | Meta Model API | `adapters/outbound/vision/spark_vision_meta_api.py` |
| SAM 3.1 | Objects and furniture in every frame, by text prompt; the arrival check | Meta Model API (optional self-hosted on Modal) | `services/pipeline/.../sam31_meta_api.py`, `services/api/.../sam31_meta_api.py` |
| MapAnything (`facebook/map-anything-apache`) | Metric 3D reconstruction from the frames, depth and poses | Mac (Apple GPU); Modal if too slow | `services/pipeline/.../mapanything_local.py` |
| Muse Voice Transcribe | Speech to text with turn detection | Meta Model API | `services/api/.../voice/muse_transcribe.py`, `apps/web/app/api/voice/transcribe/` |
| Llama Prompt Guard | Screens every message other agents send to the home memory | Mac | `services/api/.../safety/prompt_guard_local.py` |
| Muse Spark (hosted), in the demo client | A "home robot" agent that asks Recall over A2A | Meta Model API | `examples/a2a-client/home_robot.py` |

**The scan path** (minutes, in the background)
1. The iPhone walks the room and records keyframes, LiDAR depth and ARKit poses as an episode.
2. The episode uploads in resumable parts; the manifest arrives last and triggers the pipeline.
3. MapAnything rebuilds the room in metres, fed the phone's intrinsics, poses and depth.
4. The pipeline fits the floor and walls, and SAM 3.1 finds furniture (sofa, table, shelf, tv, bed, door) and objects.
5. Each find is lifted into 3D and stored as a landmark or an observation, with the time it was seen.

**The question path** (live, under 2 seconds to the first spoken words)
1. Muse Voice Transcribe turns the question into text.
2. The Guide calls `find_object`, then `describe_location`: the room, the landmark, the relation ("on the desk, left side"), the shelf level, the height band, minutes since seen.
3. "Guide me there": `localize` from the phone's ARKit pose, `plan_route` over an occupancy grid, clock-face steps spoken as you walk, taps on the Watch.
4. On arrival the Verifier checks the camera frame and the memory updates.

**OS and browser features (not model calls)**

| Feature | Used for | Where |
|---|---|---|
| LiDAR depth, ARKit tracking, ARWorldMap | Capture in metres; relocalisation for live guidance | iPhone |
| Core Motion, compass (magnetic north, no location) | Speed and turn rate for scan coaching; the scan learns where north lies in the room, so directions can say "north-east" | iPhone, Watch (stretch) |
| Haptics | Turn and arrival cues | iPhone, Apple Watch |
| VoiceOver, Dynamic Type | The app is usable without looking | iPhone, Watch |
| AVSpeechSynthesizer | Speaking answers and steps | iPhone |
| Web Speech `speechSynthesis` | Every spoken line on the website | Browser |
| Action button, Digital Crown | Start listening; repeat the last step | iPhone, Watch |
| RealityKit, Metal, WebGL | The room map on the phone and the web viewer | iPhone, browser |

## Guardrails

- **Geometry decides, the model phrases.** No location, distance or time is ever inferred by a language model; they come from tool results computed on the 3D map.
- **Grounding rules, in the prompt and enforced in code:**
  1. Never state a place, distance or time that no tool returned.
  2. Not found, or confidence under 0.5: say it hasn't been seen and suggest which room to walk.
  3. A sighting older than 24 hours is reported with its time.
  4. If tracking is limited, give landmark directions only, and say so.
  5. One or two short sentences: landmark first, then shelf and height, then time.
  6. At most 6 agent steps; on failure, the best grounded partial answer.
- **The Verifier can only downgrade.** The vision model may turn a result into "uncertain"; only SAM plus geometry can confirm.
- **Prompt Guard on the door.** Every message from an external agent is screened by Llama Prompt Guard before any tool runs.
- **Privacy.** No scan of anyone's home is in the repo or on the hosted site: raw video, frames and point clouds stay on the Mac that made them, and the viewer reads your own export from a gitignored folder. Voice clips are sent for transcription and not stored. The phone holds no API keys and talks only to our backend. In local privacy mode the agent runs on the Mac. Vercel Speed Insights: cookieless page-speed measurements, no personal data.
- **Honesty.** Sample and recorded data are labelled as such in the UI and the docs; the demo shows only what was built.
- **Rules.** Only Meta models at runtime; no non-Meta model anywhere, and no TTS model of any kind.

## Algorithms

- **Keyframe selection:** a frame is kept when the phone moved about 15 cm or turned about 10°; blurry frames are dropped by a sharpness check.
- **Pose convention:** ARKit camera-to-world poses are converted to the OpenCV convention MapAnything expects (`T @ diag(1, −1, −1, 1)`), unit tested.
- **Metric reconstruction:** MapAnything with the phone's intrinsics, poses and LiDAR depth as metric inputs, so the map is in metres and in the phone's own frame.
- **Drift check:** a Umeyama similarity transform between ARKit and MapAnything camera centres measures drift, and aligns images-only runs when phone data is missing.
- **Room model:** RANSAC plane fitting for the floor and the walls, deterministic and seeded; furniture from SAM 3.1 text prompts, lifted into 3D boxes.
- **Flat surfaces:** a height histogram of the point cloud, peaks grouped into connected patches on a 5 cm grid, thin lines rejected by fill ratio. This is what finds desk tops, seats and shelf levels.
- **Spatial relations:** "on" (within 5 cm of a surface and inside its footprint), left or right of a landmark's front, nearest landmark within 1.5 m, and five height bands (floor, knee, waist, chest, head).
- **Navigation:** an occupancy grid at 10 cm from the point cloud, A* to a reachable cell near the object, the path simplified to turns and spoken as clock-face steps.
- **Viewer:** voxel downsampling to about 150k points; a vertex shader that gathers every point from a scattered shell to its real position, floor first.

## Results so far

Measured, dated, and recorded in `docs/verification.md`. Nothing below is estimated.

- **Reconstruction speed (M5 Pro, Apple GPU):** one room, 63 frames from a 21-second phone video, MapAnything with the Apache-2.0 weights: **19.6 s** of inference, **14.8 GB** peak memory, 11.3 s to load the model.
- **Scale, images only:** two tape-measured desks (78 cm and 61 cm) came out about **23 % too large**, both by the same factor, so the shape is right and the absolute scale is not. This is why the pipeline feeds the phone's depth and poses into MapAnything; the 20 cm accuracy check waits for that run.
- **Flat surfaces:** the geometry-only detector found **12 level patches** in the room; the two largest sit at the heights of the two measured desks.
- **Viewer:** about 150k points, the gather animation, photo and confidence colouring, and the floor grid, height bands and surfaces as layers, on a phone and a laptop.
- **Web quality:** a Playwright suite covers the landing page, the viewer, accessibility (axe, WCAG 2.2 AA), reduced motion and the no-JavaScript fallbacks.

**Planned evaluation** (phase 2 onward; scored by `evals/score.py`, which uses no AI, against hand-measured positions with the ground-truth hash committed before each run): median position error, questions answered correctly, Verifier precision, and time to find an object by touch versus with Recall. The dated table will live in `evals/results.md`.

## How to run it

**Status today:** the website and the 3D viewer run. The backend, the pipeline service and the iPhone app are the next phases; their commands are marked *planned* and get filled in as they land.

### 1. The landing page and the 3D viewer (runs now)

- Requirements: Node 22 and pnpm (`corepack enable`).
- Install and start:
  ```bash
  pnpm install
  cd apps/web
  pnpm dev
  ```
- Open:
  - `http://localhost:3000/` for the landing page;
  - `http://localhost:3000/homes/flat/viewer` for your own scanned home (`flat` is the app's default home name); until it has a scan, the page lists the steps (section 2).
- Optional: "Ask by voice" on the landing page calls Muse Voice Transcribe through a server route. Create `.env` in the repo root with `META_MUSE_API_KEY=<your key>`; without it the card still works with the preset questions. Every spoken line on the site is the browser's own voice.
- Checks:
  ```bash
  pnpm lint && pnpm exec tsc --noEmit && pnpm build
  pnpm exec playwright test        # the browser suite; starts the dev server if needed
  ```

### 2. See your own room in the viewer

- Scan a room with the iPhone app and upload it to your Mac (`make live` runs the API and the scan worker; the steps are on the viewer page). The worker keeps MapAnything loaded (`recall-pipeline serve`, freed after 10 minutes idle) and starts loading it as soon as an upload begins; SAM 3.1 runs alongside the reconstruction, so a new room is ready in about a minute.
- Export the home's newest processed scan, then open `http://localhost:3000/homes/flat/viewer`:
  ```bash
  make viewer HOME_ID=flat
  ```
- Output: `apps/web/public/local-scan/<home>/` (points, photo colours, confidence, the room model and what Recall found). Git ignores the folder, so your room never leaves your computer.
- The viewer's **View** switch shows the room five ways, all computed from the scan's measurements (no generative model):
  - **Dots:** every measured point.
  - **Room model:** furniture as boxes coloured by kind, things at their measured size and colour.
  - **Surface:** the points joined into one coloured surface (Poisson reconstruction, Open3D).
  - **Photo room:** that surface painted with the scan's own photos, each patch from the photo that saw it best (checked against LiDAR depth so nothing behind a chair is painted onto it).
  - **Architect:** the room regenerated as an architect would draw it: walls squared to the room's main direction, walls the scan never saw marked as such, furniture rebuilt as parametric parts (a desk is a top on four legs) at its measured size and colour.
- Under the viewer, **Drawings** has A3 sheets drawn from the same data: a dimensioned floor plan (A1.1) and the walls seen square on from the scan's points (A2.1). The algorithms are in `services/pipeline/src/recall_pipeline/domain/` (`architecture.py`, `drawings.py`, `texturing.py`).

### 3. Backend and pipeline (planned, phases 0 to 2)

- `make setup`: Python 3.12 with uv, both services, the web app.
- `make demo`: replays a recorded sample scan and recorded model responses from `samples/replay/`, no keys, labelled as recorded output.
- `make live`: real Meta model calls with the keys from `.env`. The minimum is one Meta Model API key from [dev.meta.ai](https://dev.meta.ai) with `LLM_PROVIDER=meta`; the demo video uses Muse Spark Open on Baseten (`LLM_PROVIDER=baseten_spark_open`); the local privacy mode uses Muse Glimmer in LM Studio (`LLM_PROVIDER=lmstudio`).
- `make test`, `make lint`, `make lint-imports`: tests, ruff and ESLint, and the architecture rule (domain ← application ← adapters).

### 4. iPhone app (Watch planned, phase 3)

- XcodeGen generates the project (`cd apps/ios && xcodegen generate`); it needs an iPhone with LiDAR running iOS 26 and a free Apple ID for signing.
- In the app's Settings, enter the Mac's address (the API on your network, a Tailscale HTTPS address or a Cloudflare Tunnel URL) and the device key from `.env`. No other keys live on the phone.
- Tabs:
  - **Devices** (first; the app still opens on Find): where Recall runs. The iPhone is available now; Apple Watch Ultra 4 support is coming next and Meta AI glasses are planned, each labelled as such.
  - **Find**: ask "where are my keys?" by typing or speaking (Muse Voice Transcribe on the Mac), hear the answer, then **Take me there**. The phone relocalises in the saved room map, the Mac plans a route, and the phone speaks clock-face turns with the compass point and distance ("At 2 o'clock, north-east, 3 metres"), with a tick when you face the right way and a blue arrow over the thing in the camera view for a sighted helper. Without a map match it says the landmark and which way it lies, and ticks when you face it.
  - **Scans**: record a room, led by voice, with a step card, a top-down mini-map and the room-map state on screen; then upload it.
  - **Found**: check what Recall found and correct the name, colour or height.
  - **Settings**: the Mac's address and key, and Appearance (automatic, light or dark, plus high contrast in black, white and yellow).

### 5. Hosted version (optional)

- If a hosted copy is linked at submission, it runs in replay mode: no account and no keys needed.
- Everything also runs locally from the steps above.

### 6. Environment variables

- Keys live in `.env` at the repo root, which is never committed: `META_MUSE_API_KEY` (Meta Model API), `BASETEN_API_KEY` (Muse Spark Open on Baseten) and `RECALL_DEVICE_KEY` (any long random string; the phone pairs with it).
- `make demo` needs none. `make live` needs the Meta Model API key and, for the demo setup, the Baseten key; the Glimmer, LM Studio, A2A and R2 settings are optional.

## Not in this submission

Planned next, not built or not working yet (updated before submission; removed if everything works):

- Backend API and the pipeline service (phase 0 to 2).
- iPhone capture, upload, ask and guidance; the Watch app (phases 1 and 3).
- Agent evaluations and the Verifier precision figure (phase 2 and 4).
- The 3-minute demo video (phase 5).

## Contributing

- Until Nov 4, 2026 this is a solo hackathon entry (Indie track), so pull requests will wait until judging ends.
- After that, issues and pull requests are welcome. Please:
  1. read `CLAUDE.md` (rules, architecture, conventions);
  2. keep the dependency rule: domain code imports nothing from adapters or frameworks;
  3. use Conventional Commits, small and frequent;
  4. keep `make test`, `make lint` and the Playwright suite green;
  5. never commit secrets, raw walkthrough video or anything personal from a scan.

## Built during the hackathon

- Everything in this repo was built from scratch during the event. The repo was started on Oct 27, 2026, the day after the hackathon began.
- There is no prior work, no imported code and no earlier history; `PRIOR_WORK.md` says None.
- The commit history is the evidence of when each part was built.
- Third-party libraries and models are dependencies, never copied in; each is listed with its licence in `THIRD_PARTY.md`.

## Licence

- This repository: Apache-2.0 (see `LICENSE`).
- Models, libraries, fonts and services, each with its licence: `THIRD_PARTY.md`.
- Recall is not affiliated with or endorsed by Meta.

---

<p align="center">Built by <a href="https://www.linkedin.com/in/rachit-thariani/">Rachit Thariani</a> · <a href="https://github.com/coder-RT">GitHub</a></p>
