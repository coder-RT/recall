# Decisions

Why Recall is built the way it is, and what was rejected. Each decision has:
- **Status:** Accepted, Superseded, or In progress.
- **Deciders.**
- **Context**, **Decision** and **Alternatives** (what was rejected, and why).
- **Consequences:** + better, − worse, ~ neutral.
- **Door:**
  - **one-way:** hard to reverse later; changing it means migrating data or breaking clients.
  - **two-way:** a config or adapter swap.

The architecture these add up to is in [architecture.md](architecture.md). All decisions were made by Rachit
Thariani during the hackathon (Oct 27 to Nov 4, 2026).

**One-way doors:** D-03 single writer, D-06 episode format, D-07 home coordinate frame, D-11 Meta-only runtime,
D-28 sighting log. **Two-way doors:** everything else, notably D-10 the LLM provider, D-26 the storage adapter,
D-27 the UI libraries, D-09 the reconstructor.

---

<a id="d-01"></a>
## D-01 Hexagonal architecture (ports and adapters) with DDD aggregates
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way (the layering can be relaxed; nothing outside depends on it)
- **Context:** two services, four interchangeable model providers, two stores, a nine-day build.
- **Decision:** ports and adapters in the API and the pipeline; aggregates `Home`, `Scan`, `TrackedObject`, one
  repository each; import-linter enforces domain ← application ← adapters in CI.
- **Alternatives:**
  - A layered monolith: provider code would leak into the use cases.
  - Microservices per aggregate: a distributed monolith, for no gain.
- **Consequences:**
  - \+ A provider is swapped by config.
  - \+ The domain is tested without network or torch.
  - − Every external call needs a port.
  - ~ A little more code.

<a id="d-02"></a>
## D-02 Geometry decides facts; the language model only phrases them
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way in code, one-way in what Recall promises
- **Context:** a wrong place sends a blind person the wrong way, and "basic RAG" is a known weak pattern.
- **Decision:** spatial relations, heights, distances and times come from the 3D map through four tools. A grounding
  check in code rejects any place or number no tool returned. After one correction, the code answers from the tool
  output itself.
- **Alternatives:**
  - Let the model infer places from text labels: it invents plausible places.
  - Embedding search over descriptions: same problem, plus a vector store.
- **Consequences:**
  - \+ Answers are verifiable.
  - \+ The model can be swapped.
  - − Answers are plainer than free text.
  - ~ The grounding check has its own tests.

<a id="d-03"></a>
## D-03 One writer: the pipeline posts results, the API writes memory
- **Status:** Accepted · **Deciders:** Rachit · **Door:** one-way
- **Context:** both the scan path and the question path touch memory.
- **Decision:** `services/pipeline` never opens the database; it posts `POST /scans/{id}/results` (a spec'd
  `ScanResult`) and `ingest_scan` writes.
- **Alternatives:**
  - The pipeline writes SQLite directly: two writers, invariants in two places, and torch near the API.
- **Consequences:**
  - \+ One place decides moved, gone and new.
  - \+ Torch stays out of the API.
  - − The pipeline needs the API running.

<a id="d-04"></a>
## D-04 SQLite, one file per home; no vector database
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way (SQLAlchemy Core and Alembic; Postgres is an adapter swap)
- **Context:** one household, one writer, a memory of tens of things (140 KB after a room).
- **Decision:** SQLite with Alembic migrations; things are found by label, colour, aliases and the user's own names.
- **Alternatives:**
  - Postgres: a server to run for kilobytes.
  - A vector database: semantic search isn't how people name their keys, and a home holds tens of things, not millions.
- **Consequences:**
  - \+ Nothing to run.
  - \+ One file to back up or erase.
  - − No multi-user writes.
  - ~ A hosted multi-home version would move to Postgres.

<a id="d-05"></a>
## D-05 Scan jobs on a Huey queue backed by SQLite
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:**
  - Each upload started its own pipeline process.
  - Two jobs at once would exhaust the GPU.
  - A crash left a scan stuck in "processing".
- **Decision:**
  - `POST /complete` queues a job.
  - One worker runs one scan at a time, retries twice, then marks the scan failed with its log.
  - A nightly task re-runs every stored scan and compares the objects.
- **Alternatives:**
  - Celery: needs Redis.
  - Kafka or another streaming platform: no decision needs a stream.
  - Prefect or Dagster: their own server and UI.
  - cron: no retries or state.
- **Consequences:**
  - \+ Retries, a schedule and job state with one MIT dependency.
  - − One extra process (`make worker`).

<a id="d-06"></a>
## D-06 A scan is an episode, not a video
- **Status:** Accepted · **Deciders:** Rachit · **Door:** one-way (format `recall-episode/1`)
- **Context:** reconstruction needs metric inputs per frame, and uploads must survive a dropped connection.
- **Decision:**
  - A folder per scan: `manifest.json` (device, intrinsics, sizes, sha256 per file, capture metrics), keyframes,
    16-bit LiDAR depth in mm, ARKit confidence, and `poses.jsonl` (column-major camera-to-world, tracking state).
  - Keyframes every ~15 cm or ~10°; blurry frames are dropped.
  - Uploaded in ~8 MB parts with the manifest last.
- **Alternatives:**
  - A video file: no per-frame pose or depth; re-encoding loses detail; one dropped connection restarts everything.
- **Consequences:**
  - \+ Resumable and checksummed.
  - \+ Every frame carries its pose.
  - − A versioned format to keep compatible.
  - ~ Raw frames never go to git (privacy).

<a id="d-07"></a>
## D-07 One home coordinate frame: metres, floor at z = 0, z up
- **Status:** Accepted · **Deciders:** Rachit · **Door:** one-way
- **Context:** sightings from different scans must be comparable, and robots need a map frame.
- **Decision:**
  - Each scan is moved into the home frame.
  - A rescan the phone recognises (in the saved ARKit world map) shares the first scan's frame and is compared.
  - An unrecognised rescan starts that room's memory afresh rather than guessing an alignment.
- **Alternatives:**
  - Each scan in its own frame: no "what changed".
  - Always forcing an alignment: a wrong match would move everything.
- **Consequences:**
  - \+ "What changed" is geometry.
  - \+ The robot export is a valid Nav2 map.
  - − Changing the frame later means migrating every sighting.

<a id="d-08"></a>
## D-08 MapAnything with the phone's metric inputs
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way (see D-09)
- **Context:**
  - Images-only reconstruction came out about 23 % too large.
  - The non-commercial weights would block an open licence.
- **Decision:**
  - `facebook/map-anything-apache` (Apache-2.0, pinned revision).
  - Fed ARKit intrinsics, poses (converted to the OpenCV convention, unit tested) and LiDAR depth as metric inputs.
  - Umeyama measures drift.
  - Runs on the Mac's GPU, about 20 s a room; Modal is the overflow.
- **Alternatives:**
  - Images-only: wrong scale.
  - VGGT: same scale problem.
  - Apple's room scanning: an Apple model, not allowed.
- **Consequences:**
  - \+ Metric output in the phone's frame.
  - − 14.8 GB peak GPU memory, so never alongside LM Studio.
  - ~ Organizers confirmed MapAnything counts as a Meta model.

<a id="d-09"></a>
## D-09 A model-free reconstruction fallback
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way (`RECONSTRUCTOR=mapanything|arkit_depth`)
- **Context:** a backup if MapAnything were ruled out or the GPU were busy.
- **Decision:** back-project the LiDAR depth with ARKit intrinsics and poses, behind the same `Reconstructor` port.
- **Alternatives:**
  - Open3D TSDF fusion: smoother, but the port wants per-frame geometry.
  - Another model: same rules question.
- **Consequences:**
  - \+ On the real living room, all 10 objects landed within 2 to 7 cm of the MapAnything run.
  - \+ Reconstruction takes 0.2 s.
  - − Uses only depth the LiDAR saw (≤ 5 m).

<a id="d-10"></a>
## D-10 The Guide runs on Muse Spark Open (Baseten), at low reasoning effort
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way (`LLM_PROVIDER`, `GUIDE_REASONING_EFFORT`)
- **Context:**
  - The Guide should run on Meta's open weights.
  - The first measurement took 4.2 s per question.
  - Baseten runs the model at `xhigh` reasoning by default.
- **Decision:**
  - Muse Spark Open on Baseten at `reasoning_effort: low`.
  - `find_object` returns each match's place, so one tool call answers.
  - Alternatives by config: Glimmer on LM Studio (stays on the Mac), Glimmer on Modal or Fireworks, hosted Muse Spark.
  - All use one OpenAI-compatible adapter.
- **Alternatives:**
  - The default reasoning effort: same answers, twice the time.
  - Answering from a template without a model: fast, but Meta's model no longer phrases anything.
- **Consequences:**
  - \+ Median 2.3 s, p90 2.7 s, from 4.2 s and 5.9 s.
  - \+ The safety check at `low` still blocked 0 of 21 normal names and passed 0 of 18 attacks.
  - − Depends on Baseten's uptime; the other providers are the fallback.

<a id="d-11"></a>
## D-11 Meta models only at runtime
- **Status:** Accepted · **Deciders:** Rachit, following the organizers' rulings · **Door:** one-way
- **Context:** the hackathon rules.
- **Decision:**
  - At runtime: Muse Spark Open and Glimmer (Guide), Muse Spark 1.1 (arrival tie-break), SAM 3.1, MapAnything, Muse
    Voice Transcribe.
  - OS features that aren't model calls are fine: ARKit tracking, LiDAR, VoiceOver, AVSpeechSynthesizer, Web Speech.
- **Alternatives:** none.
- **Consequences:**
  - \+ Every model is accounted for in the README's "What runs where".
  - − No Apple speech recognition, no Apple room scanning, no text-to-speech model.

<a id="d-12"></a>
## D-12 Classic geometry for the room: Open3D and Shapely, no ML modules
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:** the room model needs cleaned points, a floor, walls and outlines.
- **Decision:**
  - Open3D: voxel downsampling, outlier removal, seeded RANSAC planes (floor first, then walls), FPFH + ICP
    registration.
  - Shapely: the floor polygon and footprints.
  - No ML module of any library.
- **Alternatives:**
  - A learned layout model: not a Meta model.
  - Hand-written RANSAC: works, but harder to maintain.
- **Consequences:**
  - \+ Deterministic.
  - \+ A synthetic room in CI checks walls within 10 cm.
  - − Cluttered rooms give extra wall pieces.

<a id="d-13"></a>
## D-13 One object per label by clustering; one landmark per piece of furniture
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:**
  - SAM sees one mug in many frames.
  - One desk came back as both "table" and "desk", and from several sides (22 boxes for 10 pieces).
- **Decision:**
  - Lift each box into 3D with depth.
  - DBSCAN per label.
  - Merge same-kind furniture that overlaps; the label with the most evidence wins.
- **Alternatives:**
  - SAM's video tracking: `TODO(verify)` that the API offers it.
  - A larger clustering radius: merges separate desks.
- **Consequences:**
  - \+ One mug, one memory.
  - − Two desks pushed together become one, as a person would describe them.

<a id="d-14"></a>
## D-14 Moved, new and gone by optimal assignment
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:** a rescan must tell moved from new from gone without a model guess.
- **Decision:**
  - Same-label things are matched to the room's last scan with `linear_sum_assignment` on 3D distance.
  - A thing that moved more than 30 cm becomes a new sighting, and the old place is set aside.
  - A thing outside the rescan's view is left alone, not marked gone.
- **Alternatives:**
  - Greedy nearest neighbour: swaps two mugs.
  - Asking the model: never.
- **Consequences:**
  - \+ "What changed" lists only real changes.
  - − Identical things that swap places look unchanged.

<a id="d-15"></a>
## D-15 Routes keep to the middle of free space
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:** a shortest path hugs furniture; a blind walker needs room.
- **Decision:**
  - Occupancy grid (10 cm), clearance from a distance transform, obstacles inflated by a 0.3 m body radius.
  - A* with a cost near obstacles.
  - "No safe path" falls back to landmark directions.
- **Alternatives:**
  - Plain A*: hugs edges.
  - A visibility graph: corner-cutting.
- **Consequences:**
  - \+ Tested on a synthetic corridor (stays centred) and a narrow gap (refuses).
  - − Very tight rooms get landmark directions only.

<a id="d-16"></a>
## D-16 Look-alikes: colour from pixels, the user's corrections win
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:** a home has several bags and books.
- **Decision:**
  - The pipeline names each thing's colour from the pixels in its box, with 12 basic names and a vote across
    sightings.
  - The user can name, recolour, move, confirm or remove a thing.
  - Corrections are stored apart and win over measurements.
- **Alternatives:**
  - Describing each crop with a vision model: a model call per thing, and harder to ground.
- **Consequences:**
  - \+ "Your grey bag or your white bag?"
  - − Weak for thin or dark things; the review screen covers those.

<a id="d-17"></a>
## D-17 Warm starts on both ends
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:** cold starts made the first scan and the first guide slow.
- **Decision:**
  - The Mac keeps MapAnything loaded in a warm server (freed after 10 minutes idle) and starts SAM calls before
    reconstruction finishes.
  - The phone starts recognising the room while the answer is read out.
- **Alternatives:**
  - Loading the model per job: 20 s every time.
  - Keeping it loaded forever: blocks LM Studio.
- **Consequences:**
  - \+ A room went from 143 s to 60 s.
  - − The camera starts after an answer even if the person never walks there (at most a minute).

<a id="d-18"></a>
## D-18 Speech: Muse Voice Transcribe in, the OS voice out
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way for the voice, one-way for "no TTS model" (rules)
- **Context:** the rules forbid other speech models and any TTS model.
- **Decision:**
  - Speech to text through Muse Voice Transcribe.
  - Speech out through AVSpeechSynthesizer, or VoiceOver's own voice when it's on.
  - On the website, Web Speech.
  - The phone says what it is looking for the moment it has the question.
- **Alternatives:**
  - Apple's speech recognition: not allowed.
  - A neural voice: not allowed.
- **Consequences:**
  - \+ The user's own voice and rate.
  - \+ Works offline for output.
  - − No offline voice input; typing is the fallback.

<a id="d-19"></a>
## D-19 `make demo` replays a recorded real run
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:** the repo must run from the README, and judges have no keys.
- **Decision:**
  - The demo builds memory from a recorded scan result through the real ingest code.
  - It replays Muse Spark Open's recorded replies by question and step, at the recording's time.
  - Every answer is labelled `replay:muse-spark-open (recorded)`.
- **Alternatives:**
  - Mock data: not allowed to present as real.
  - Requiring keys: judges couldn't run it.
- **Consequences:**
  - \+ Runs anywhere in seconds.
  - − Only recorded questions are answered, and it says so.

<a id="d-20"></a>
## D-20 Robots and agents: A2A 1.0 and a Nav2 export, off by default
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:** robots and other agents could use the same memory; a home must stay private.
- **Decision:**
  - The Home Memory agent over A2A 1.0 (JSON-RPC), mounted in the API.
  - A robot export (Nav2 map, things, furniture).
  - Both are behind a Robot Access switch on the phone (off by default), with their own read-only key and every
    request audited.
- **Alternatives:**
  - A custom REST endpoint: agents would need custom code.
  - Always on: privacy.
- **Consequences:**
  - \+ Standard protocol.
  - \+ The owner sees every robot request.
  - − Robots must send structured requests (D-21).

<a id="d-21"></a>
## D-21 Inbound screening: structure first, then a Meta-model check, fail closed
- **Status:** Accepted (replaced an earlier screening model that the organizers ruled out) · **Deciders:** Rachit ·
  **Door:** two-way
- **Context:** unknown agents send requests to a home's memory.
- **Decision:**
  1. A2A skills accept only `{"object": "<name>"}`: letters, digits, spaces and hyphens, at most 40 characters.
     Free text never reaches a model or a tool.
  2. Muse Spark Open (or Glimmer) returns strict JSON `{"verdict": "safe" | "injection"}`.
  3. Invalid JSON, a timeout or "injection" refuses the request.
- **Alternatives:**
  - A keyword list: brittle.
  - A non-Meta guard model: not allowed.
- **Consequences:**
  - \+ Measured: 0 of 21 normal names blocked, 0 of 18 instruction-like names passed.
  - − About 1 s per robot request.

<a id="d-22"></a>
## D-22 Arrival check: SAM 3.1 and geometry decide; a vision model may only downgrade
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:** "You've arrived" must be true.
- **Decision:**
  - One camera frame goes to SAM 3.1; the box is lifted with LiDAR depth into the home frame; the 30 cm rule decides.
  - Muse Spark 1.1 is asked only when SAM is unsure, and may only move a result to "uncertain".
  - Seen nearby updates memory.
  - It runs in-process; A2A is optional.
- **Alternatives:**
  - Asking a vision model "is it there?": it would confirm things that aren't.
- **Consequences:**
  - \+ 3 cm off on the real keys, in 4.9 s.
  - − Needs the LiDAR.

<a id="d-23"></a>
## D-23 No login, no account
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:** judges must never need an account; the owner is one household.
- **Decision:**
  - A pairing key between the phone and the Mac, and a separate robot key.
  - No user accounts, no auth server.
- **Alternatives:**
  - Accounts with JWT and Postgres: a server for nothing.
- **Consequences:**
  - \+ Nothing to sign up for.
  - − One owner per Mac.

<a id="d-24"></a>
## D-24 Logs, traces and the audit trail stay on the Mac
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:** failures must leave a trace without sending data anywhere.
- **Decision:**
  - JSON-lines request logs (no headers or bodies) and OpenTelemetry traces in `data/logs/`, sent to a collector only
    when asked.
  - An append-only audit table: who did what, by key, kept 90 days.
- **Alternatives:**
  - A hosted tracing service: needs an account, and data leaves the home.
- **Consequences:**
  - \+ Every robot request and every erase is on record.
  - − Logs live on the Mac only.

<a id="d-25"></a>
## D-25 Erasing a scan reaches the Mac
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:** deleting a scan on the phone used to leave its photos and things on the Mac.
- **Decision:**
  - `DELETE /scans/{id}` (owner only; not while processing) removes the scan's files, log and regression copy, and
    what memory learnt only from it.
  - Erasing a room's newest scan puts back what it changed.
  - The phone asks first and says what it reaches.
- **Alternatives:**
  - Files only: memory would keep things nobody can see the evidence for.
  - Re-ingesting the room's other scans: loses the user's corrections.
- **Consequences:**
  - \+ The privacy note can promise it.
  - − Erasing an older scan keeps the newer scans' view.

<a id="d-26"></a>
## D-26 Storage behind a port: the Mac's disk, R2 optional
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way (`STORAGE=local|r2`)
- **Context:** episodes are tens of MB; the default must work with no account.
- **Decision:** a `BlobStore` port; local disk by default; an S3-compatible R2 adapter for multipart uploads.
- **Alternatives:**
  - Cloud only: needs an account and sends photos away.
- **Consequences:**
  - \+ Local first.
  - ~ R2 is ready when the Mac isn't always on.

<a id="d-27"></a>
## D-27 Web: Next.js, GSAP for scroll, Motion for UI, react-three-fiber for the viewer
- **Status:** Accepted · **Deciders:** Rachit · **Door:** two-way
- **Context:** a landing page that tells the story, and a 3D viewer of a real scan.
- **Decision:**
  - GSAP owns scroll scenes and Motion owns UI state, never both on one element.
  - The viewer reads compact binary point clouds.
  - Content is visible without JavaScript; WCAG 2.2 AA with an accessibility menu.
- **Alternatives:**
  - One animation library for everything: GSAP is better at scroll, Motion at state.
- **Consequences:**
  - \+ 143 end-to-end tests, including keyboard-only and 200 % text usability.
  - − Two animation libraries to know.

<a id="d-28"></a>
## D-28 Sightings are an append-only log
- **Status:** Accepted (migration 0007) · **Deciders:** Rachit · **Door:** one-way
- **Context:** every answer should be traceable to what the camera saw.
- **Decision:**
  - A sighting is never edited.
  - "Set aside" (moved, gone, a fresh start) is its own append-only record, and "where is it now" is derived.
  - Each sighting names its scan, keyframe and box; each scan records the model versions that produced it.
  - Every answer is logged with its model and tool steps and the sightings it rests on (`answer_log`).
  - Database triggers refuse updates to sightings, set-asides and logged answers.
  - Erasing a scan for privacy is the one deletion, and it's in the audit trail. It also deletes the set-asides that
    scan decided, so the earlier memory comes back by itself.
- **Alternatives:**
  - A `stale` flag updated in place: history is lost and answers can't be explained.
- **Consequences:**
  - \+ "Why do you think so?" has an answer: `GET /answers/{id}/evidence`, the phone's "Why?" sheet, and the Guide's
    `explain` tool.
  - \+ An answer that names a place with no sighting behind it is never said (tested).
  - − Two more tables (`set_asides`, `answer_log`).
