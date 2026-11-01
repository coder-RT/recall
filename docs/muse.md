# Meta Muse in Recall

Recall uses Meta's Muse family in two ways:

- **At runtime**, Muse models hear the question, choose the tools, word the answer, double-check an uncertain arrival
  and screen what outside agents send. Geometry decides every fact; Muse turns the facts into speech.
- **During development**, Meta's **Muse Code** (v1.4.14) tested and audited the repository with three tiers of agents.
  Its findings were checked against the code and fixed. The commits are listed below.

Part A is about the product. Part B is about how it was tested.

---

## Part A: the Muse models Recall runs

The Guide, the screen and the voice input are the core of the live question path. Every one of them is a Muse model.

### 1. Muse Voice Transcribe: turns a spoken question into text

- **What:** speech to text, with turn detection (`mode: "ENDPOINTING"`), so Recall knows when the person has finished
  speaking.
- **Why:** Recall is voice-first for blind and low-vision people. It is the only speech model in Recall: no Apple
  on-device speech recognition and no other vendor.
- **How, in order:**
  1. The phone (or the website's "Ask by voice") records mono 16-bit WAV.
  2. The Mac posts it to the Meta Model API with the `muse-voice-transcribe-1.0` model.
  3. Only the words are kept. The audio isn't stored, and the audit log records that audio was sent, never the words.
- **Code:**
  - `services/api/src/recall_api/adapters/outbound/voice/muse_transcribe.py` (the adapter);
  - `application/transcribe_speech.py` (the use case, audited);
  - `apps/web/app/api/voice/transcribe/route.ts` (the website).

### 2. Muse Spark Open: the Guide agent

- **What:** the language model that understands "where are my keys?", calls Recall's tools and words a one- or
  two-sentence spoken answer.
- **Why:** it can call tools and phrase things naturally, with open weights (`meta-models/muse-spark-open-1026`).
  It never decides a fact. Places, distances and times come from the 3D map.
- **How, in order:**
  1. The question goes to `AskWhereIs` with the five tools from `resources/tools.json`: `find_object`,
     `describe_location`, `localize`, `plan_route` and `explain`.
  2. Spark Open picks a tool. Recall runs it on the geometry (spatial relations, height bands, the last sighting).
  3. The tool result goes back, and Spark Open words the answer: landmark first, then shelf and height, then when.
  4. The grounding rules are in the prompt and checked in code (`domain/assistant`). An answer that names a place no
     tool returned is not spoken.
  5. There are at most 6 steps. It runs at `reasoning_effort: low` on Baseten (median 2.3 s to the answer over 10
     real questions; see `docs/verification.md`).
- **Code:**
  - `application/ask_where_is.py` (the agent loop);
  - `adapters/outbound/llm/openai_compatible.py` (one OpenAI-compatible adapter for every Muse provider);
  - `infra/container.py` (picks the provider from `LLM_PROVIDER`).

### 3. Muse Glimmer: private mode

- **What:** the same Guide on Muse Glimmer, run by LM Studio on the Mac (`LLM_PROVIDER=lmstudio`).
- **Why:** the questions never leave the home. Hosted Glimmer (Modal or Fireworks) is another option.
- **How:** the same adapter and tools. Only the base URL and model change, in `infra/container.py`.

### 4. Muse Spark 1.1: the Verifier's tie-break

- **What:** a multimodal check on one camera frame when you arrive.
- **Why:** SAM 3.1 plus the LiDAR depth decide whether the thing is really there. When SAM's score is low, Spark 1.1
  is asked whether the thing can be seen in the photo.
- **How:** its answer can only **lower** a result to "uncertain", never confirm one. "Unsure" or any unclear reply
  changes nothing.
- **Code:** `application/verify_arrival.py` and `adapters/outbound/vision/spark_vision_meta_api.py`, reached through
  the `ArrivalVerifier` port (in-process).

### 5. Muse Spark Open (or Glimmer) as a screen for outside agents

- **What:** before a robot or another app's agent gets an answer from the Home Memory agent (A2A 1.0), the object name
  it sent is checked.
- **Why:** free text from outside must never steer a model or a tool.
- **How, in order:**
  1. The schema allows one object name (letters, digits, spaces, hyphens, at most 40 characters).
  2. Muse Spark Open returns a strict JSON verdict, `{"verdict": "safe" | "injection"}`.
  3. Anything else, such as bad JSON, a timeout or an error, refuses the request: it **fails closed**.
- **Code:** `adapters/outbound/safety/meta_model_screen.py` and `application/answer_external_query.py`.

### 6. Replay: Muse's real replies, recorded

- **What:** `make demo` runs with no keys by replaying recorded Muse Spark Open replies to a real scan.
- **Why:** judges can try Recall without accounts. The output is labelled as recorded.
- **Code:** `adapters/outbound/replay/recorded_llm.py`.

The other Meta models in the pipeline are MapAnything (metric 3D) and SAM 3.1 (finding furniture and things). They
are covered in the README under "How it works: the Meta models".

---

## Part B: how Muse Code tested Recall

On 1 November 2026, Rachit asked Meta's Muse Code (v1.4.14) to test the whole repository three times without getting
stuck, check the hexagonal architecture, and then audit security. Muse Code ran these as **workflows**: small programs
that spawn agents in parallel and in sequence.

### The mechanism

- Muse Code writes a workflow program. `host.parallel([...])` starts agents side by side, and `host.agent({...})`
  runs one stage after another.
- Each agent returns a `ref`. The next stage receives the refs, and the runtime attaches the earlier results, so no
  files are passed between agents.
- Every agent answers in the same strict shape: `{complete, evidence[], unresolved[]}`.
  - **Evidence** is one line per claim, with the severity, the claim, a `path:line` and the test that covers it.
  - **Unresolved** holds what the agent could not decide, and why.
  - A search result alone was not accepted as evidence. The agent had to open the file.

### Run 1: testing, in three tiers

```
 Tier 1 (side by side)        Tier 2              Tier 3
 ┌──────────┐  ┌──────────┐
 │  Tester  │  │ Reviewer │ ─▶  Tie-breaker  ─▶  Synthesis (the only writer)
 └──────────┘  └──────────┘
```

- **Tester:** the only agent allowed to run tests.
  - It ran `make test-all` once, then the API and pipeline suites twice more, plus lint and the import contracts each
    time.
  - **Anti-loop contract:** one attempt per command per run, a time limit, and "blocked, with the exact error"
    instead of retries.
  - It compared the three runs test by test. The results were identical, with no flaky tests.
- **Reviewer:** read-only, and not allowed to run suites, so it could never compete with the tester for test
  databases.
  - It read every layer's imports, the ports, both composition roots and the import-linter contracts.
  - Then it opened the test behind each claim.
- **Tie-breaker:** received both results and every disagreement, and re-read the code itself.
  - Example: it identified the 5 erroring pipeline tests as one test file's fixture from the test collection and
    the log's shape, without running anything again.
- **Synthesis:** the only agent that wrote files. It wrote the test report and a quality checklist (code, pipeline,
  UI and algorithms).

### Run 2: security, in two tiers

- **Three surface auditors, side by side:**
  - **Backend:** SQL injection sinks, the authorisation matrix per route, the agent and prompt-injection path,
    traversal and SSRF, rate limits and secrets.
  - **Web:** XSS sinks, the contact and voice routes, security headers, client secrets and the lockfiles.
  - **iPhone and Watch:** every free-text field, pairing links, the Keychain, Watch messages, App Transport Security
    and timeouts.
- **Rule for all three:** no live attacks. Static reading and local read-only commands only; nothing was sent to a
  deployed site.
- **Synthesis:** wrote the security review and checklist.
- **Camera review, done inline without agents:** Muse Code traced the camera path end to end (capture, storage, upload,
  what reaches Meta's models, erase). A single depth-first topic is better read by one reader than split across
  hand-offs.

### What Muse Code found

| Area | Finding | Fixed in |
|---|---|---|
| Tests | `torch.mps.empty_cache()` could end the pipeline with a signal on a machine without an Apple GPU | `1c404bb` |
| Watch | A lost iPhone reply left the Watch on "thinking" forever | `02c5f97` |
| Architecture | Logic in two routers, memory writes outside use cases, `util` not checked by import-linter, no test enforcing either rule | `91b0964` (routers only map, one writer, enforced by an AST test) |
| Contract | No Schemathesis suite, though the docs said so | `f70aeb9`. Its first run found two real contract bugs (an undocumented 401, and FastAPI's 422 shape) |
| Docs | Verifier port, later-scan alignment and an example client described but not built | `1622596`, `9bf56e8` |
| Security (high) | A pairing link could silently point the phone at another server | `446cc96` (asks first) |
| Security (high) | The camera and microphone prompts said data goes "only to your own Mac", but photos go to SAM 3.1 and voice to Muse Voice Transcribe | `446cc96` (the prompts now name them; a contract test keeps them honest) |
| Security (medium) | Bare host as http; the key sent to off-host URLs; the key on the clipboard; the pipeline server open without a key; job paths writable anywhere; no rate limits | `446cc96`, `f4804d8`, `08262e5` |
| Security (low) | Zip bomb, body sizes, NaN in results, no web security headers, no robots.txt, question audio left on the device, Watch message sizes | `08262e5`, `dc7866c`, `446cc96` |

It also confirmed what was **safe**:
- SQL queries all use bound parameters;
- the outside-agent screen fails closed;
- the website has no XSS sinks;
- secrets live only in the Keychain;
- there is no video and no face detection, the arrival frame stays in memory, and Meta's models receive photos only,
  never depth.

### Honest limits

- **Test failures from the sandbox.** Muse Code ran in a sandbox that couldn't open network ports, write some caches
  or start the iOS Simulator. So several red results (socket errors, iOS "blocked") were sandbox artefacts. On the
  Mac every suite passes: API, pipeline, web, iOS unit and UI, and the Watch build.
- **Findings rechecked.** Every finding was checked against the code before fixing. Two didn't hold:
  - bidi characters were already stripped (a test was added);
  - an offline delete already keeps the phone's copy.
- **Workflow scripts.** The workflow runner needed single-line scripts after multi-line ones failed to compile. A
  one-line probe found the cause.

### Why three tiers

- **Breadth in parallel, agreement in sequence.** Two independent views (running tests vs reading code) catch
  different things. The tie-breaker turns disagreements into evidence instead of guesses.
- **One writer.** Only the synthesis agent writes files, so agents never overwrite each other. This is the same rule
  Recall's API follows for the home's memory.
- **Evidence or "unresolved".** Every claim carries a file and line, or is listed as open. That is why each finding
  above could be checked and fixed.
